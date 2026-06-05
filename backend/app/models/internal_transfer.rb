# RF11 — transferência interna entre contas do mesmo workspace (saída numa
# conta + entrada de mesmo valor em outra). Não conta como gasto/receita nos
# relatórios (RF11.2). Pode ser detectada automaticamente (confirmed_by nil) ou
# marcada manualmente (RF11.4).
class InternalTransfer < ApplicationRecord
  belongs_to :workspace
  belongs_to :debit_transaction,  class_name: "Transaction"
  belongs_to :credit_transaction, class_name: "Transaction"
  belongs_to :confirmed_by_membership, class_name: "WorkspaceMembership", optional: true

  validates :debit_transaction_id,  uniqueness: true
  validates :credit_transaction_id, uniqueness: true
  validate :directions_match
  validate :different_accounts
  validate :same_workspace

  # True se foi marcada por um humano; false se veio da detecção automática.
  def manual?
    confirmed_by_membership_id.present?
  end

  private

  def directions_match
    errors.add(:debit_transaction, "deve ser um débito") if debit_transaction && debit_transaction.direction != "debit"
    errors.add(:credit_transaction, "deve ser um crédito") if credit_transaction && credit_transaction.direction != "credit"
  end

  def different_accounts
    return if debit_transaction.nil? || credit_transaction.nil?
    return if debit_transaction.account_id != credit_transaction.account_id

    errors.add(:base, "as contas devem ser diferentes")
  end

  def same_workspace
    return if debit_transaction.nil? || credit_transaction.nil?
    ids = [ debit_transaction.workspace_id, credit_transaction.workspace_id ].uniq
    return if ids == [ workspace_id ]

    errors.add(:base, "transações devem ser do mesmo workspace")
  end
end
