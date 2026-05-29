# Registro de uma alteração num campo de uma transação (RF4.3 — trilha de
# auditoria leve entre o casal). Um por campo alterado em cada edição.
class TransactionEdit < ApplicationRecord
  # `txn` porque `transaction` colide com um método interno do ActiveRecord.
  belongs_to :txn, class_name: "Transaction", foreign_key: :transaction_id
  belongs_to :edited_by_membership, class_name: "WorkspaceMembership"

  validates :field_name, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
