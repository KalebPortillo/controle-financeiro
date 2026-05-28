module BankConnections
  # Puxa transações novas de todas as accounts de uma conexão e cria
  # Transactions na inbox (status pending). Idempotente: dedup pela coluna
  # gerada external_transaction_id (unique por account).
  #
  # `provider` injetável (fake nos testes, Pluggy real via job). RF2: tudo
  # cai como pending pra revisão humana — pré-categorização (RF3) entra depois.
  class Sync
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(connection:, provider: default_provider)
      @connection = connection
      @provider   = provider
    end

    def call
      created = 0
      duplicated = 0

      @connection.accounts.find_each do |account|
        next if account.external_id.blank?

        @provider.list_transactions(
          account_id: account.external_id,
          from:       @connection.sync_history_since
        ).each do |t|
          if import_transaction(account, t)
            created += 1
          else
            duplicated += 1
          end
        end
      end

      @connection.update!(last_sync_at: Time.current, status: "connected", error_message: nil)
      { created: created, duplicated: duplicated }
    end

    private

    # Retorna true se criou, false se já existia (dedup). A unicidade é
    # garantida no DB (external_transaction_id gerado); capturamos a violação
    # pra contar como duplicado sem abortar o sync inteiro.
    def import_transaction(account, t)
      amount = t.fetch(:amount).to_f
      Transaction.create!(
        workspace:            account.workspace,
        account:              account,
        direction:            amount.negative? ? "debit" : "credit",
        amount_cents:         (amount.abs * 100).round,
        currency:             t[:currency_code] || "BRL",
        occurred_at:          Date.parse(t[:date].to_s),
        original_description: t[:description].presence || "(sem descrição)",
        status:               "pending",
        source:               "automatic_sync",
        source_metadata:      t[:raw] || { "id" => t[:id] }
      )
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end

    def default_provider
      BankAggregators::Pluggy.new(
        client_id:     ENV.fetch("PLUGGY_CLIENT_ID"),
        client_secret: ENV.fetch("PLUGGY_CLIENT_SECRET")
      )
    end
  end
end
