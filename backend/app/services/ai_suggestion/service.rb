module AiSuggestion
  # Pipeline principal de sugestão para uma transação.
  # Ordem: regras manuais (futuro) → regras aprendidas → API → fallback.
  class Service
    ONBOARDING_THRESHOLD = 0

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(transaction:, provider: nil)
      @transaction = transaction
      @workspace   = transaction.workspace
      @provider    = provider || default_provider
    end

    def call
      # 1. Regras aprendidas
      descriptor = Normalizer.call(@transaction.original_description)
      rule = AiLearnedRule.lookup(workspace_id: @workspace.id, descriptor: descriptor)
      return learned_result(rule) if rule

      # 2. API — modo onboarding ou normal
      context = ContextExtractor.call(@transaction)
      existing_tags = @workspace.tags.pluck(:id, :name).map { |id, name| { id: id, name: name } }

      if existing_tags.size <= ONBOARDING_THRESHOLD
        onboarding_suggest(context)
      else
        normal_suggest(context, existing_tags)
      end
    rescue AiProviders::ApiError => e
      # 429 é relançado — o job tem retry_on com backoff exponencial.
      raise if e.message.include?("429")
      Rails.logger.warn("[AiSuggestion] falhou para tx #{@transaction.id}: #{e.message}")
      fallback
    rescue AiProviders::ConfigurationError, StandardError => e
      Rails.logger.warn("[AiSuggestion] falhou para tx #{@transaction.id}: #{e.message}")
      fallback
    end

    private

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

    def normal_suggest(context, existing_tags)
      result = @provider.suggest(context: context, existing_tags: existing_tags)
      result.merge(suggested_new_tags: [], source: "api")
    end

    def onboarding_suggest(context)
      ctx_with_id = context.merge(id: @transaction.id)
      results = @provider.suggest_batch(transactions_context: [ ctx_with_id ])
      item = results.find { |r| r[:transaction_id].to_s == @transaction.id.to_s } || {}
      {
        improved_title:     item[:improved_title],
        suggested_tag_ids:  [],
        new_tag_suggestion: nil,
        suggested_new_tags: item[:suggested_new_tags] || [],
        confidence:         item[:confidence],
        source:             "api_onboarding"
      }
    end

    def fallback
      { improved_title: nil, suggested_tag_ids: [], new_tag_suggestion: nil,
        suggested_new_tags: [], confidence: nil, source: "fallback" }
    end

    def default_provider
      AiProviders::GeminiProvider.new
    end
  end
end
