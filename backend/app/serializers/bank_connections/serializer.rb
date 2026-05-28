module BankConnections
  # Schema canônico de uma conexão bancária no JSON da API (RF21). Compartilhado
  # entre o controller (REST) e o broadcast do Action Cable, pra que o payload
  # em tempo real bata exatamente com o da listagem.
  class Serializer
    INSTITUTION_LABELS = {
      "nubank" => "Nubank", "inter" => "Inter", "itau" => "Itaú",
      "santander" => "Santander", "bb" => "Banco do Brasil",
      "sandbox" => "Sandbox", "manual" => "Manual"
    }.freeze

    def self.call(connection)
      new(connection).as_json
    end

    def initialize(connection)
      @connection = connection
    end

    def as_json(*)
      {
        id:                 @connection.id,
        provider:           @connection.provider,
        status:             @connection.status,
        error_message:      @connection.error_message,
        sync_history_since: @connection.sync_history_since.iso8601,
        last_sync_at:       @connection.last_sync_at&.iso8601,
        next_sync_at:       @connection.next_sync_at&.iso8601,
        last_sync_created_count:    @connection.last_sync_created_count,
        last_sync_duplicate_count:  @connection.last_sync_duplicate_count,
        last_sync_error_count:      @connection.last_sync_error_count,
        last_sync_duration_seconds: @connection.last_sync_duration_seconds,
        accounts: @connection.accounts.sort_by(&:created_at).map { |a| account(a) }
      }
    end

    private

    def account(acc)
      {
        id:                acc.id,
        name:              acc.name,
        kind:              acc.kind,
        institution:       acc.institution,
        institution_label: INSTITUTION_LABELS[acc.institution],
        currency:          acc.currency
      }
    end
  end
end
