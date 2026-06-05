require "net/http"
require "json"

module AiProviders
  class GeminiProvider < Provider
    BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models".freeze
    # Conexão deve ser rápida; a geração em lote (onboarding) pode demorar, então
    # o read tem folga maior pra não estourar com prompts grandes (RF22).
    OPEN_TIMEOUT_SEC = 10
    READ_TIMEOUT_SEC = 30

    # Performance (RF22): pra tarefa estruturada de classificação não precisamos do
    # raciocínio interno do 2.5-flash (thinking) — desligá-lo (thinkingBudget: 0) é
    # o maior ganho de latência/tokens. maxOutputTokens limita a saída ao JSON
    # esperado (~25 itens em lote cabem folgado), e temperature baixa torna a
    # classificação determinística. Vale pros 2 fluxos (inbox + onboarding).
    MAX_OUTPUT_TOKENS = 2048
    TEMPERATURE       = 0.2

    # Erros de rede crus do Net::HTTP. Convertidos em ApiError pra que o
    # retry_on dos jobs (AnalyzeJob/BatchSuggestJob) os capture e re-tente com backoff,
    # em vez de matar o job e prender o onboarding em "analyzing".
    NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
      Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH,
      SocketError, IOError, OpenSSL::SSL::SSLError
    ].freeze

    # Diretriz de taxonomia para a IA: tags devem ser TEMAS AMPLOS e reutilizáveis,
    # não estabelecimentos. Reaproveitada nos prompts de onboarding e da inbox pra
    # manter consistência (RF3/RF22). Ex.: Netflix → "Assinaturas", iFood →
    # "Alimentação". Sem isso a IA sugere nomes específicos demais ("Netflix").
    TAG_TAXONOMY_GUIDANCE = <<~GUIDE.freeze
      As tags devem ser TEMAS AMPLOS e reutilizáveis que descrevam o TIPO de gasto —
      nunca o nome do estabelecimento ou da marca. Exemplos de boas tags:
      "Alimentação", "Transporte", "Assinaturas", "Contas da casa", "Saúde",
      "Lazer", "Entretenimento", "Compras", "Educação", "Mensalidades recorrentes".
      Regras:
      - NUNCA use nome de empresa/loja como tag. "Netflix"/"Spotify" → "Assinaturas";
        "iFood"/"restaurante X" → "Alimentação"; "Uber"/"99" → "Transporte".
      - Prefira poucas tags abrangentes a muitas específicas; reutilize a mesma tag
        para gastos do mesmo tema.
    GUIDE

    def initialize(api_key: nil, model: nil)
      @api_key = api_key || ENV.fetch("GEMINI_API_KEY", nil)
      @model   = model   || ENV.fetch("AI_MODEL", "gemini-2.5-flash")
    end

    def suggest(context:, existing_tags:)
      prompt = build_normal_prompt(context, existing_tags)
      raw    = call_api(prompt)
      parse_normal_response(raw)
    end

    def suggest_batch(transactions_context:)
      prompt = build_onboarding_prompt(transactions_context)
      raw    = call_api(prompt)
      parse_batch_response(raw)
    end

    # Inbox em lote (P2): classifica VÁRIAS transações numa só chamada, com as
    # tags existentes do workspace. Mesma semântica do `suggest` de 1 tx, mas
    # por lote. Retorna [{ transaction_id, improved_title, suggested_tag_ids,
    # new_tag_suggestion, confidence }].
    def suggest_inbox_batch(transactions_context:, existing_tags: [])
      prompt = build_inbox_batch_prompt(transactions_context, existing_tags)
      raw    = call_api(prompt)
      parse_inbox_batch_response(raw)
    end

    # Descoberta inicial de tags + categorias (RF22 onboarding).
    # transactions_context: array de hashes com :id, :description, :merchant_name etc.
    # existing_tags/categories: nomes em PT-BR a EXCLUIR (modo aditivo).
    # Retorna { tags: [{name, rationale, coverage}], categories: [{name, tag_names}] }
    def suggest_onboarding_discovery(transactions_context:, existing_tags: [], existing_categories: [])
      prompt = build_discovery_prompt(transactions_context, existing_tags, existing_categories)
      raw    = call_api(prompt)
      parse_discovery_response(raw)
    end

    # 2ª análise do onboarding (RF22): a partir das tags JÁ aceitas pelo usuário,
    # sugere categorias amplas que as agrupem. Cada categoria vem com o subconjunto
    # de tag_names (só dentre as aceitas). Retorna [{name, tag_names}].
    def suggest_categories_from_tags(tag_names:)
      return [] if Array(tag_names).empty?

      prompt = build_categories_prompt(tag_names)
      raw    = call_api(prompt)
      parse_categories_response(raw)
    end

    private

    def call_api(prompt)
      raise AiProviders::ConfigurationError, "GEMINI_API_KEY not set" if @api_key.blank?

      uri = URI("#{BASE_URL}/#{@model}:generateContent?key=#{@api_key}")
      body = {
        contents: [ { parts: [ { text: prompt } ] } ],
        generationConfig: {
          responseMimeType: "application/json",
          thinkingConfig:   { thinkingBudget: 0 },
          maxOutputTokens:  MAX_OUTPUT_TOKENS,
          temperature:      TEMPERATURE
        }
      }

      req      = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = OPEN_TIMEOUT_SEC
      http.read_timeout = READ_TIMEOUT_SEC

      res = http.request(req)
      raise AiProviders::ApiError, "Gemini HTTP #{res.code}: #{res.body[0, 200]}" unless res.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(res.body)
      payload.dig("candidates", 0, "content", "parts", 0, "text").to_s
    rescue *NETWORK_ERRORS => e
      raise AiProviders::ApiError, "Gemini network error: #{e.class}: #{e.message}"
    end

    def build_normal_prompt(ctx, existing_tags)
      tags_json = existing_tags.map { |t| { id: t[:id], name: t[:name] } }.to_json
      <<~PROMPT
        Você é um assistente de finanças pessoais. Dado o gasto abaixo, retorne JSON:
        {
          "improved_title": "Nome legível em PT-BR (máx 50 chars)",
          "suggested_tag_ids": ["uuid1"],
          "new_tag_suggestion": "nome da tag nova" | null,
          "confidence": "high" | "medium" | "low"
        }
        Regras:
        - Priorize sempre tags existentes. Sugira tag nova só se nenhuma encaixar.
        - improved_title deve ser conciso e em PT-BR.
        - confidence: high = certeza, medium = provável, low = chute.

        Tags disponíveis: #{tags_json}

        Gasto:
        - Descrição: #{ctx[:description]}
        - Estabelecimento: #{ctx[:merchant_name]} (CNAE: #{ctx[:merchant_cnae]})
        - Categoria do banco: #{ctx[:pluggy_category]}
        - Método: #{ctx[:payment_method]}
        - Destinatário: #{ctx[:receiver_name]}
        - Valor: R$ #{format('%.2f', ctx[:amount])} (#{ctx[:direction]})
      PROMPT
    end

    def build_onboarding_prompt(txs)
      list = txs.map do |t|
        { id: t[:id], description: t[:description], merchant: t[:merchant_name],
          category: t[:pluggy_category], method: t[:payment_method],
          receiver: t[:receiver_name], amount: t[:amount], direction: t[:direction] }
      end.to_json

      <<~PROMPT
        Você é um assistente de finanças pessoais. O usuário não tem nenhuma tag criada.
        Analise as transações abaixo e retorne um array JSON, uma entrada por transação, na mesma ordem:
        [
          {
            "transaction_id": "...",
            "improved_title": "Nome legível em PT-BR (máx 50 chars)",
            "suggested_new_tags": ["Tag1", "Tag2"],
            "confidence": "high" | "medium" | "low"
          }
        ]
        Regras:
        - Seja consistente: o mesmo tipo de gasto deve receber a mesma tag.
        - Máximo 2 tags por transação.

        #{TAG_TAXONOMY_GUIDANCE}
        Transações: #{list}
      PROMPT
    end

    def build_inbox_batch_prompt(txs, existing_tags)
      tags_json = existing_tags.map { |t| { id: t[:id], name: t[:name] } }.to_json
      list = txs.map do |t|
        { id: t[:id], description: t[:description], merchant: t[:merchant_name],
          category: t[:pluggy_category], method: t[:payment_method],
          receiver: t[:receiver_name], amount: t[:amount], direction: t[:direction] }
      end.to_json

      <<~PROMPT
        Você é um assistente de finanças pessoais. Classifique as transações
        abaixo e retorne um array JSON, uma entrada por transação, na mesma ordem:
        [
          {
            "transaction_id": "...",
            "improved_title": "Nome legível em PT-BR (máx 50 chars)",
            "suggested_tag_ids": ["id de tag existente"],
            "new_tag_suggestion": "nome de tag nova" | null,
            "confidence": "high" | "medium" | "low"
          }
        ]
        Regras:
        - Priorize sempre tags existentes. Sugira tag nova só se nenhuma encaixar.
        - improved_title conciso e em PT-BR. confidence: high = certeza,
          medium = provável, low = chute.
        - Seja consistente: o mesmo tipo de gasto deve receber as mesmas tags.

        #{TAG_TAXONOMY_GUIDANCE}
        Tags disponíveis: #{tags_json}

        Transações: #{list}
      PROMPT
    end

    def build_discovery_prompt(txs, existing_tags, existing_categories)
      list = txs.map do |t|
        {
          id: t[:id], description: t[:description], merchant: t[:merchant_name],
          category: t[:pluggy_category], method: t[:payment_method],
          receiver: t[:receiver_name], amount: t[:amount], direction: t[:direction]
        }
      end.to_json

      exclude_clause = ""
      if existing_tags.any? || existing_categories.any?
        exclude_clause = <<~EXC
          IMPORTANTE — modo aditivo: NÃO sugira tags com nomes em
          #{existing_tags.to_json} nem categorias em #{existing_categories.to_json}.
          Sugira só o que ainda falta no catálogo.
        EXC
      end

      <<~PROMPT
        Você é um assistente de finanças pessoais. Analise as transações
        abaixo e descubra a taxonomia que melhor descreve o padrão de gastos
        do usuário.

        Retorne JSON:
        {
          "tags": [
            {
              "name": "Nome em PT-BR (1-3 palavras, máx 30 chars)",
              "rationale": "frase curta dizendo por que essa tag aparece",
              "coverage": número-aproximado-de-transações-que-encaixam
            }
          ],
          "categories": [
            {
              "name": "Nome em PT-BR (1-3 palavras)",
              "tag_names": ["nomes de tags do array acima que pertencem aqui"]
            }
          ]
        }
        Regras:
        - Categorias agrupam tags por afinidade (uma tag pode estar em + de
          uma categoria).
        - Ordene tags por coverage decrescente.
        - Apenas tags com cobertura >= 1 transação.

        #{TAG_TAXONOMY_GUIDANCE}
        #{exclude_clause}

        Transações: #{list}
      PROMPT
    end

    def build_categories_prompt(tag_names)
      <<~PROMPT
        Você é um assistente de finanças pessoais. O usuário já escolheu estas
        tags para o seu catálogo:
        #{Array(tag_names).to_json}

        Agrupe-as em CATEGORIAS amplas (uma categoria reúne tags afins). Retorne JSON:
        {
          "categories": [
            {
              "name": "Nome da categoria em PT-BR (1-3 palavras)",
              "tag_names": ["apenas nomes que estão na lista de tags acima"]
            }
          ]
        }
        Regras:
        - Use SOMENTE tags da lista fornecida; não invente tags novas.
        - Uma tag pode estar em mais de uma categoria.
        - Toda tag deve aparecer em ao menos uma categoria, se fizer sentido.
        - Nomes de categoria amplos e reutilizáveis (ex.: "Essenciais", "Moradia",
          "Lazer", "Transporte", "Saúde").
      PROMPT
    end

    def parse_categories_response(raw)
      data = JSON.parse(raw)
      Array(data["categories"]).map do |c|
        {
          name:      c["name"].to_s.strip,
          tag_names: Array(c["tag_names"]).map { |n| n.to_s.strip }.reject(&:empty?)
        }
      end.reject { |c| c[:name].empty? }
    rescue JSON::ParserError
      []
    end

    def parse_discovery_response(raw)
      data = JSON.parse(raw)
      {
        tags: Array(data["tags"]).map do |t|
          {
            name:      t["name"].to_s.strip,
            rationale: t["rationale"].to_s.strip,
            coverage:  t["coverage"].to_i
          }
        end.reject { |t| t[:name].empty? },
        categories: Array(data["categories"]).map do |c|
          {
            name:      c["name"].to_s.strip,
            tag_names: Array(c["tag_names"]).map { |n| n.to_s.strip }.reject(&:empty?)
          }
        end.reject { |c| c[:name].empty? }
      }
    rescue JSON::ParseError
      { tags: [], categories: [] }
    end

    def parse_normal_response(raw)
      data = JSON.parse(raw)
      {
        improved_title:    data["improved_title"].presence,
        suggested_tag_ids: Array(data["suggested_tag_ids"]).map(&:to_s),
        new_tag_suggestion: data["new_tag_suggestion"].presence,
        confidence:        data["confidence"].presence
      }
    rescue JSON::ParseError
      fallback_result
    end

    def parse_batch_response(raw)
      data = JSON.parse(raw)
      Array(data).map do |item|
        {
          transaction_id:    item["transaction_id"].to_s,
          improved_title:    item["improved_title"].presence,
          suggested_new_tags: Array(item["suggested_new_tags"]).map(&:to_s).first(2),
          confidence:        item["confidence"].presence
        }
      end
    rescue JSON::ParseError
      []
    end

    def parse_inbox_batch_response(raw)
      data = JSON.parse(raw)
      Array(data).map do |item|
        {
          transaction_id:     item["transaction_id"].to_s,
          improved_title:     item["improved_title"].presence,
          suggested_tag_ids:  Array(item["suggested_tag_ids"]).map(&:to_s),
          new_tag_suggestion: item["new_tag_suggestion"].presence,
          confidence:         item["confidence"].presence
        }
      end
    rescue JSON::ParserError
      []
    end

    def fallback_result
      { improved_title: nil, suggested_tag_ids: [], new_tag_suggestion: nil, confidence: nil }
    end
  end
end
