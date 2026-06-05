module AiSuggestion
  # Executa o pipeline de sugestão para uma única transação e persiste o
  # resultado (improved_title + ai_confidence + snapshot + tags) via Persist.
  # Mantido pra compatibilidade; o caminho corrente é BatchSuggestJob (lote).
  class SuggestJob < ApplicationJob
    queue_as :ai_suggestion

    # Gemini free tier: 15 RPM. Retry em 429 com backoff exponencial.
    retry_on AiProviders::ApiError, wait: :polynomially_longer, attempts: 5

    def perform(transaction_id)
      tx = Transaction.find_by(id: transaction_id)
      return unless tx&.pending?

      result = AiSuggestion::Service.call(transaction: tx)
      AiSuggestion::Persist.call(tx, result)
    end
  end
end
