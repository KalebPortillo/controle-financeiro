module AiSuggestion
  # Executa o pipeline de sugestão para uma única transação e persiste
  # improved_title + ai_confidence no registro.
  # Enfileirado pelo SyncJob após cada importação.
  class SuggestJob < ApplicationJob
    queue_as :ai_suggestion

    # Gemini free tier: 15 RPM. Retry em 429 com backoff exponencial.
    retry_on AiProviders::ApiError, wait: :polynomially_longer, attempts: 5

    def perform(transaction_id)
      tx = Transaction.find_by(id: transaction_id)
      return unless tx&.pending?

      result = AiSuggestion::Service.call(transaction: tx)

      ActiveRecord::Base.transaction do
        updates = {}
        updates[:improved_title] = result[:improved_title] if result[:improved_title].present?
        updates[:ai_confidence]  = confidence_to_decimal(result[:confidence]) if result[:confidence]
        tx.update_columns(updates) if updates.any?

        # Aplica tags sugeridas existentes (modo normal)
        if result[:suggested_tag_ids].present?
          existing = tx.workspace.tags.where(id: result[:suggested_tag_ids])
          tx.tags = existing if existing.any?
        end

        # Modo onboarding: cria tags novas e aplica
        if result[:suggested_new_tags].present? && tx.tags.empty?
          new_tags = result[:suggested_new_tags].map do |name|
            tx.workspace.tags.find_or_create_by!(name: name.strip.truncate(50))
          end
          tx.tags = new_tags
        end
      end
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
