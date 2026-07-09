# RF9.7 — transação que o usuário removeu manualmente do grupo de uma
# recorrência. O casamento da recorrência é dinâmico por descritor (RF9.1); a
# exclusão é a válvula de escape pra tirar um gasto avulso que caiu no padrão.
class RecurrenceExclusion < ApplicationRecord
  belongs_to :recurrence
  # "transaction" é método do ActiveRecord — usamos excluded_transaction.
  belongs_to :excluded_transaction, class_name: "Transaction", foreign_key: :transaction_id
  belongs_to :workspace

  validates :transaction_id, uniqueness: { scope: :recurrence_id }
end
