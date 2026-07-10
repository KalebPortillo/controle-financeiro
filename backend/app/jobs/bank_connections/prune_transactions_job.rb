module BankConnections
  # Assíncrono sobre BankConnections::PruneTransactions — dispara no webhook
  # `transactions/deleted` do Pluggy (WebhooksController#pluggy).
  class PruneTransactionsJob < ApplicationJob
    queue_as :default

    def perform(bank_connection_id, external_ids)
      connection = BankConnection.find_by(id: bank_connection_id)
      return unless connection

      BankConnections::PruneTransactions.call(connection: connection, external_ids: external_ids)
    end
  end
end
