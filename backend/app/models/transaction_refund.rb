# RF10 — vínculo de um estorno (transação credit) ao gasto original (debit).
# O valor consolidado efetivo do gasto é calculado por query (ver
# Transaction#effective_amount_cents), nunca mutado em coluna. Todo vínculo
# passa por confirmação humana (RF10.5), registrada em confirmed_by_membership.
class TransactionRefund < ApplicationRecord
  # manual = confirmado por humano (RF10.5); automatic = match de código exato
  # único no sync/backfill (RF10.6), sem membership.
  ORIGINS = %w[manual automatic].freeze

  belongs_to :refund_transaction,   class_name: "Transaction"
  belongs_to :refunded_transaction, class_name: "Transaction"
  belongs_to :confirmed_by_membership, class_name: "WorkspaceMembership", optional: true

  # Um crédito estorna no máximo um gasto (também garantido por índice unique).
  validates :refund_transaction_id, uniqueness: true
  validates :origin, inclusion: { in: ORIGINS }
  validate :refund_is_credit
  validate :refunded_is_debit
  validate :same_workspace

  def automatic?
    origin == "automatic"
  end

  private

  def refund_is_credit
    return if refund_transaction.nil? || refund_transaction.direction == "credit"

    errors.add(:refund_transaction, "deve ser um crédito")
  end

  def refunded_is_debit
    return if refunded_transaction.nil? || refunded_transaction.direction == "debit"

    errors.add(:refunded_transaction, "deve ser um débito")
  end

  def same_workspace
    return if refund_transaction.nil? || refunded_transaction.nil?
    return if refund_transaction.workspace_id == refunded_transaction.workspace_id

    errors.add(:base, "estorno e gasto devem ser do mesmo workspace")
  end
end
