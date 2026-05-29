module AiProviders
  ConfigurationError = Class.new(StandardError)
  ApiError           = Class.new(StandardError)

  class Provider
    # Modo normal (tags existem no workspace).
    # Retorna: { improved_title:, suggested_tag_ids:, new_tag_suggestion:, confidence: }
    def suggest(context:, existing_tags:)
      raise NotImplementedError
    end

    # Modo onboarding (sem tags). Processa um lote de transações.
    # `transactions_context` = array de hashes com :id + campos do ContextExtractor.
    # Retorna: array de { transaction_id:, improved_title:, suggested_new_tags:, confidence: }
    def suggest_batch(transactions_context:)
      raise NotImplementedError
    end
  end
end
