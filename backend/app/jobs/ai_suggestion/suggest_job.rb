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

      return if result[:source] == "fallback"

      ActiveRecord::Base.transaction do
        # Tags sugeridas (modo normal: IDs existentes; onboarding: nomes novos)
        applied_tags = resolve_tags(tx, result)

        updates = {}
        updates[:improved_title] = result[:improved_title] if result[:improved_title].present?
        updates[:ai_confidence]  = confidence_to_decimal(result[:confidence]) if result[:confidence]

        # Snapshot persistente do que a IA sugeriu — base do histórico no UI.
        updates[:ai_suggestion] = {
          "title"        => result[:improved_title],
          "tag_ids"      => applied_tags.map(&:id),
          "tag_names"    => applied_tags.map(&:name),
          "new_tags"     => result[:suggested_new_tags] || [],
          "confidence"   => result[:confidence],
          "source"       => result[:source],
          "suggested_at" => Time.current.iso8601
        }

        tx.update_columns(updates) if updates.any?
        tx.tags = applied_tags if applied_tags.any?
      end
    end

    private

    def resolve_tags(tx, result)
      if result[:suggested_tag_ids].present?
        tx.workspace.tags.where(id: result[:suggested_tag_ids]).to_a
      elsif result[:suggested_new_tags].present? && tx.tags.empty?
        result[:suggested_new_tags].map do |name|
          tx.workspace.tags.find_or_create_by!(name: name.strip.truncate(50))
        end
      else
        []
      end
    end

    def confidence_to_decimal(level)
      case level
      when "high"   then 0.9
      when "medium" then 0.6
      when "low"    then 0.3
      end
    end
  end
end
