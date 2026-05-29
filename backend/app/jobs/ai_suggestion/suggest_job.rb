module AiSuggestion
  # Executa o pipeline de sugestão para uma única transação e persiste
  # improved_title + ai_confidence no registro.
  # Enfileirado pelo SyncJob após cada importação.
  class SuggestJob < ApplicationJob
    queue_as :default

    def perform(transaction_id)
      tx = Transaction.find_by(id: transaction_id)
      return unless tx&.pending?

      result = AiSuggestion::Service.call(transaction: tx)

      updates = {}
      updates[:improved_title] = result[:improved_title] if result[:improved_title].present?
      updates[:ai_confidence]  = confidence_to_decimal(result[:confidence]) if result[:confidence]

      tx.update_columns(updates) if updates.any?
    end

    private

    def confidence_to_decimal(level)
      case level
      when "high"   then 0.9
      when "medium" then 0.6
      when "low"    then 0.3
      end
    end
  end
end
