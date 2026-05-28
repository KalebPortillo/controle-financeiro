module BankConnections
  # Persiste uma conexão bancária a partir de um item do Pluggy (já criado
  # pelo widget no frontend) + popula as accounts daquele item.
  #
  # Idempotente: se a conexão (provider + external_connection_id) já existe,
  # reusa; accounts são upsertadas por (bank_connection_id, external_id).
  #
  # `provider` é injetável (default = BankAggregators::Pluggy real) pra
  # testes usarem um fake. Camadas: service orquestra, provider é o adapter.
  class Create
    # Pluggy account.type → nosso kind
    KIND_BY_PLUGGY_TYPE = {
      "BANK"   => "checking",
      "CREDIT" => "credit_card"
    }.freeze

    # connector_id do Pluggy → nossa institution enum
    INSTITUTION_BY_CONNECTOR = {
      612 => "nubank",
      2   => "sandbox"
    }.freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(workspace:, owner_membership:, item_id:, history_since:, provider: default_provider)
      @workspace        = workspace
      @owner_membership = owner_membership
      @item_id          = item_id
      @history_since    = history_since
      @provider         = provider
    end

    def call
      item = @provider.get_item(item_id: @item_id)

      ActiveRecord::Base.transaction do
        connection = upsert_connection(item)
        upsert_accounts(connection, item)
        connection
      end
    end

    private

    def upsert_connection(item)
      connection = BankConnection.find_or_initialize_by(
        provider:               "pluggy",
        external_connection_id: @item_id
      )
      connection.workspace          = @workspace
      connection.owner_membership   = @owner_membership
      connection.sync_history_since = @history_since
      connection.status             = map_status(item[:status])
      connection.error_message      = nil
      connection.save!
      connection
    end

    def upsert_accounts(connection, item)
      institution = INSTITUTION_BY_CONNECTOR.fetch(item[:connector_id], "manual")

      @provider.list_accounts(item_id: @item_id).each do |a|
        account = Account.find_or_initialize_by(
          bank_connection_id: connection.id,
          external_id:        a[:id]
        )
        account.workspace        = @workspace
        account.owner_membership = @owner_membership
        account.name             = a[:name]
        account.kind             = KIND_BY_PLUGGY_TYPE.fetch(a[:type], "checking")
        account.institution      = institution
        account.currency         = a[:currency_code] || "BRL"
        account.save!
      end
    end

    # Pluggy item status → nosso enum de BankConnection.
    def map_status(pluggy_status)
      case pluggy_status
      when "UPDATED", "CREATED" then "connected"
      when "UPDATING"           then "syncing"
      when "LOGIN_ERROR"        then "expired"
      when "OUTDATED", "ERROR"  then "error"
      else "connected"
      end
    end

    def default_provider
      BankAggregators::Pluggy.new(
        client_id:     ENV.fetch("PLUGGY_CLIENT_ID"),
        client_secret: ENV.fetch("PLUGGY_CLIENT_SECRET")
      )
    end
  end
end
