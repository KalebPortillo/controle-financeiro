module AiSuggestion
  # Aprende com a correção do usuário (RF3.2).
  # Disparado quando um TransactionEdit é criado para improved_title ou tags.
  class RecordCorrectionJob < ApplicationJob
    queue_as :default

    def perform(transaction_id)
      tx = Transaction.find_by(id: transaction_id)
      return unless tx

      descriptor = AiSuggestion::Normalizer.call(tx.original_description)
      return if descriptor.blank?

      AiLearnedRule.upsert(
        {
          workspace_id:       tx.workspace_id,
          descriptor_pattern: descriptor,
          improved_title:     tx.improved_title.presence,
          tag_ids:            tx.tags.pluck(:id),
          match_count:        1,
          last_seen_at:       Time.current,
          created_at:         Time.current,
          updated_at:         Time.current
        },
        on_duplicate: Arel.sql(
          "improved_title = EXCLUDED.improved_title, " \
          "tag_ids = EXCLUDED.tag_ids, " \
          "match_count = ai_learned_rules.match_count + 1, " \
          "last_seen_at = EXCLUDED.last_seen_at, " \
          "updated_at = EXCLUDED.updated_at"
        ),
        unique_by: :index_ai_learned_rules_on_workspace_and_pattern
      )
    end
  end
end
