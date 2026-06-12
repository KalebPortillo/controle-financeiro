module Transactions
  # Edição em grupo de um parcelamento (RF9.4.1): aplica improved_title e/ou tags
  # a TODAS as parcelas do mesmo installment_group_id no workspace. Valor e data
  # NÃO mudam (são por parcela). Registra um TransactionEdit por campo alterado
  # por parcela (RF4.3) e dispara o aprendizado uma vez (mesmo descritor).
  #
  # `attrs` traz só as chaves que o usuário enviou (:improved_title e/ou :tag_ids).
  module UpdateInstallmentGroup
    module_function

    def call(workspace:, group_id:, membership:, attrs:)
      transactions = workspace.transactions.where(installment_group_id: group_id).to_a
      raise ActiveRecord::RecordNotFound, "installment group not found" if transactions.empty?

      tags = (workspace.tags.where(id: Array(attrs[:tag_ids]).map(&:to_s)).to_a if attrs.key?(:tag_ids))
      changed_any = false

      ActiveRecord::Base.transaction do
        transactions.each do |t|
          changed_any = true if apply_to(t, attrs, tags, membership)
        end
      end

      enqueue_learning(transactions.first) if changed_any
      transactions.each(&:reload)
    end

    # Aplica os campos a uma parcela; registra edits dos que mudaram. Retorna true
    # se algo mudou.
    def apply_to(t, attrs, tags, membership)
      before_tags = t.tags.pluck(:id).sort
      t.improved_title = attrs[:improved_title] if attrs.key?(:improved_title)
      scalar_changes = t.changes.slice("improved_title")
      t.tags = tags if tags
      t.save!

      record_edits(t, membership, scalar_changes, before_tags)
      scalar_changes.any? || (tags && t.tags.reload.pluck(:id).sort != before_tags)
    end

    def record_edits(t, membership, scalar_changes, before_tags)
      return unless membership

      scalar_changes.each do |field, (old_v, new_v)|
        t.edits.create!(edited_by_membership: membership, field_name: field,
                        old_value: old_v, new_value: new_v)
      end

      after_tags = t.tags.reload.pluck(:id).sort
      return if after_tags == before_tags

      t.edits.create!(edited_by_membership: membership, field_name: "tags",
                      old_value: before_tags, new_value: after_tags)
    end

    def enqueue_learning(transaction)
      AiSuggestion::RecordCorrectionJob.perform_later(transaction.id)
    end
  end
end
