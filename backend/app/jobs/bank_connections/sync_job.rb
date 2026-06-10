module BankConnections
  # Wrapper assíncrono (Solid Queue) sobre BankConnections::Sync. Carrega a
  # conexão, marca como syncing, roda o sync com o provider real e trata erro
  # marcando o status pra UI (RF21).
  class SyncJob < ApplicationJob
    queue_as :default

    def perform(bank_connection_id)
      connection = BankConnection.find(bank_connection_id)
      previous_status = connection.status
      connection.update!(status: "syncing")
      BankConnections::Sync.call(connection: connection)
    rescue BankAggregators::AuthenticationError, BankAggregators::ItemError => e
      connection&.update(status: "expired", error_message: e.message)
      notify_failure(connection, previous_status, e)
      raise
    rescue BankAggregators::Error => e
      connection&.update(status: "error", error_message: e.message)
      notify_failure(connection, previous_status, e)
      raise
    end

    private

    # RF21.6: notificação in-app na PRIMEIRA falha. Conexão que já estava
    # quebrada não re-notifica (retries do Solid Queue e webhooks repetidos do
    # Pluggy chegariam aqui de novo); o dedup por dia é o cinto extra.
    ALREADY_BROKEN = %w[error expired].freeze

    def notify_failure(connection, previous_status, error)
      return if connection.nil? || ALREADY_BROKEN.include?(previous_status)

      institution = connection.accounts.first&.institution
      Notifications::Create.call(
        workspace: connection.workspace,
        kind:      "sync_failed",
        dedup_key: "sync_failed:#{connection.id}:#{Date.current}",
        payload:   {
          "bank_connection_id" => connection.id,
          "institution_label"  => BankConnections::Serializer::INSTITUTION_LABELS[institution] || "banco",
          "error_message"      => error.message
        }
      )
    end
  end
end
