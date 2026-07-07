# RF23 — vínculo tipado entre um gasto de origem (primary) e uma transação
# satélite (related): IOF, tarifa, juros ou ajuste. O IOF é auto-detectado no
# sync (origin: "automatic"); vínculo manual vem depois (Fase 3). Estorno NÃO
# usa esta tabela — vive em TransactionRefund; a view "relacionadas" une as duas.
class TransactionLink < ApplicationRecord
  RELATION_TYPES = %w[iof fee interest adjustment].freeze
  ORIGINS        = %w[automatic manual].freeze

  belongs_to :workspace
  belongs_to :primary_transaction, class_name: "Transaction"
  belongs_to :related_transaction, class_name: "Transaction"
  belongs_to :confirmed_by_membership, class_name: "WorkspaceMembership", optional: true

  validates :relation_type, presence: true, inclusion: { in: RELATION_TYPES }
  validates :origin,        presence: true, inclusion: { in: ORIGINS }
  # Um satélite pertence a no máximo um gasto por tipo (também no índice unique).
  validates :related_transaction_id, uniqueness: { scope: :relation_type }
  validate :distinct_transactions
  validate :same_workspace

  attribute :origin, default: "automatic"

  private

  def distinct_transactions
    return if primary_transaction_id.nil? || related_transaction_id.nil?
    return if primary_transaction_id != related_transaction_id

    errors.add(:related_transaction, "não pode ser a própria transação de origem")
  end

  def same_workspace
    return if primary_transaction.nil? || related_transaction.nil?
    return if primary_transaction.workspace_id == related_transaction.workspace_id

    errors.add(:base, "origem e relacionada devem ser do mesmo workspace")
  end
end
