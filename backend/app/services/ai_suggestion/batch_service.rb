module AiSuggestion
  # Pipeline de sugestão em LOTE (P2). Mesma ordem do Service de 1 tx, mas para
  # várias transações: regras aprendidas primeiro (short-circuit, sem API), e o
  # restante numa ÚNICA chamada ao provider. Devolve um hash { tx_id => result },
  # onde cada result tem o mesmo formato de AiSuggestion::Service.call.
  #
  # Assume que todas as transações pertencem ao mesmo workspace (o dispatch
  # fatia por workspace).
  class BatchService
    ONBOARDING_THRESHOLD = 0

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(transactions:, provider: nil)
      @transactions = Array(transactions)
      @workspace    = @transactions.first&.workspace
      @provider     = provider || AiProviders::GeminiProvider.new
    end

    def call
      return {} if @transactions.empty?

      results = {}
      pending = []

      # 1. Regras aprendidas — não vão pra API.
      @transactions.each do |tx|
        descriptor = Normalizer.call(tx.original_description)
        rule = AiLearnedRule.lookup(workspace_id: @workspace.id, descriptor: descriptor)
        if rule
          results[tx.id] = learned_result(rule)
        else
          pending << tx
        end
      end

      # 2. Resto numa única chamada (modo onboarding ou inbox).
      results.merge!(api_results(pending)) if pending.any?
      results
    end

    private

    def api_results(txs)
      existing_tags = @workspace.tags.pluck(:id, :name).map { |id, name| { id: id, name: name } }
      onboarding    = existing_tags.size <= ONBOARDING_THRESHOLD

      contexts = txs.map { |tx| ContextExtractor.call(tx).merge(id: tx.id) }
      items    = onboarding ? @provider.suggest_batch(transactions_context: contexts)
                            : @provider.suggest_inbox_batch(transactions_context: contexts, existing_tags: existing_tags)

      by_id = items.index_by { |i| i[:transaction_id].to_s }
      txs.each_with_object({}) do |tx, acc|
        acc[tx.id] = build_result(by_id[tx.id.to_s] || {}, onboarding)
      end
    rescue AiProviders::ApiError
      # Erros de IA SOBEM pro job, que registra no workspace pra UI (feedback) e
      # decide retry (transitório) vs descarte (quota). Sem fallback silencioso.
      raise
    rescue AiProviders::ConfigurationError => e
      # Chave ausente/config inválida = IA indisponível pro usuário.
      raise AiProviders::ApiError.new(e.message, reason: :unavailable)
    rescue StandardError => e
      # Bug inesperado (não-IA): degrada por tx pra não derrubar o lote inteiro.
      Rails.logger.warn("[AiSuggestion::Batch] falhou para lote de #{txs.size}: #{e.message}")
      fallback_for(txs)
    end

    def build_result(item, onboarding)
      if onboarding
        {
          improved_title:     item[:improved_title],
          suggested_tag_ids:  [],
          new_tag_suggestion: nil,
          suggested_new_tags: item[:suggested_new_tags] || [],
          confidence:         item[:confidence],
          source:             "api_onboarding"
        }
      else
        {
          improved_title:     item[:improved_title],
          suggested_tag_ids:  item[:suggested_tag_ids] || [],
          new_tag_suggestion: item[:new_tag_suggestion],
          suggested_new_tags: [],
          confidence:         item[:confidence],
          source:             "api"
        }
      end
    end

    def learned_result(rule)
      {
        improved_title:     rule.improved_title,
        suggested_tag_ids:  rule.tag_ids || [],
        new_tag_suggestion: nil,
        suggested_new_tags: [],
        confidence:         "high",
        source:             "learned"
      }
    end

    def fallback_for(txs)
      txs.each_with_object({}) { |tx, acc| acc[tx.id] = fallback }
    end

    def fallback
      { improved_title: nil, suggested_tag_ids: [], new_tag_suggestion: nil,
        suggested_new_tags: [], confidence: nil, source: "fallback" }
    end
  end
end
