# Marca uma transação sincronizada que o usuário excluiu, pra o sync não trazê-la
# de volta. Chaveia pela ASSINATURA DE CONTEÚDO (não pelo id do Pluggy, que muda
# em PENDING→POSTED). Ver BankConnections::Sync#import_transaction.
class TransactionTombstone < ApplicationRecord
  belongs_to :workspace
  belongs_to :account

  SIGNATURE_KEYS = %i[occurred_at amount_cents direction original_description].freeze

  # Assinatura de conteúdo de uma transação (pra gravar/consultar tombstone).
  def self.signature_for(transaction)
    { account_id: transaction.account_id }.merge(
      SIGNATURE_KEYS.index_with { |k| transaction.public_send(k) }
    )
  end

  # Idempotente — excluir duas vezes a mesma assinatura não estoura.
  def self.record!(transaction)
    find_or_create_by!(signature_for(transaction)) do |tombstone|
      tombstone.workspace_id = transaction.workspace_id
    end
  end
end
