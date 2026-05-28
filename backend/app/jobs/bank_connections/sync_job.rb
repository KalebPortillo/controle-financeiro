module BankConnections
  # Wrapper assíncrono (Solid Queue) sobre BankConnections::Sync. Carrega a
  # conexão, marca como syncing, roda o sync com o provider real e trata erro
  # marcando o status pra UI (RF21).
  class SyncJob < ApplicationJob
    queue_as :default

    def perform(bank_connection_id)
      connection = BankConnection.find(bank_connection_id)
      connection.update!(status: "syncing")
      BankConnections::Sync.call(connection: connection)
    rescue BankAggregators::AuthenticationError, BankAggregators::ItemError => e
      connection&.update(status: "expired", error_message: e.message)
      raise
    rescue BankAggregators::Error => e
      connection&.update(status: "error", error_message: e.message)
      raise
    end
  end
end
