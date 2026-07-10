module BankConnections
  # Two-way sync (docs.pluggy.ai/docs/setup-two-way-sync-with-webhooks): quando o
  # Pluggy consolida os dados ele apaga transações e avisa por `transactions/deleted`
  # com os ids afetados. Removemos as linhas correspondentes — mas SÓ as que ainda
  # estão `pending` (não revisadas). Já consolidada/rejeitada é decisão humana e
  # entra em relatório; não apagamos silenciosamente (uma pendente→postada real é
  # tratada pela reconciliação por conteúdo no Sync, não aqui).
  class PruneTransactions
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(connection:, external_ids:)
      @connection   = connection
      @external_ids = Array(external_ids).map(&:to_s).reject(&:blank?)
    end

    def call
      return 0 if @external_ids.empty?

      scope = Transaction
              .joins(:account)
              .where(accounts: { bank_connection_id: @connection.id })
              .where(source: "automatic_sync", status: "pending")
              .where(external_transaction_id: @external_ids)

      scope.destroy_all.size
    end
  end
end
