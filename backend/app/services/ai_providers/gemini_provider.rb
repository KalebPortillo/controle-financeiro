require "net/http"
require "json"

module AiProviders
  class GeminiProvider < Provider
    BASE_URL    = "https://generativelanguage.googleapis.com/v1beta/models".freeze
    TIMEOUT_SEC = 10

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

    private

    def call_api(prompt)
      raise AiProviders::ConfigurationError, "GEMINI_API_KEY not set" if @api_key.blank?

      uri = URI("#{BASE_URL}/#{@model}:generateContent?key=#{@api_key}")
      body = {
        contents: [ { parts: [ { text: prompt } ] } ],
        generationConfig: { responseMimeType: "application/json" }
      }

      req      = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = true
      http.open_timeout = TIMEOUT_SEC
      http.read_timeout = TIMEOUT_SEC

      res = http.request(req)
      raise AiProviders::ApiError, "Gemini HTTP #{res.code}: #{res.body[0, 200]}" unless res.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(res.body)
      payload.dig("candidates", 0, "content", "parts", 0, "text").to_s
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
        - Prefira nomes genéricos e reutilizáveis (ex.: "Mercado", "Delivery", "Transporte").
        - Máximo 2 tags por transação.

        Transações: #{list}
      PROMPT
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

    def fallback_result
      { improved_title: nil, suggested_tag_ids: [], new_tag_suggestion: nil, confidence: nil }
    end
  end
end
