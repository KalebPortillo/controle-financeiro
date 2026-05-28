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
      errored = 0
      started = Time.current

      @connection.accounts.find_each do |account|
        next if account.external_id.blank?

        @provider.list_transactions(
          account_id: account.external_id,
          from:       @connection.sync_history_since
        ).each do |t|
          case import_transaction(account, t)
          when :created    then created += 1
          when :duplicated then duplicated += 1
          when :errored    then errored += 1
          end
        end
      end

      finished = Time.current
      @connection.update!(
        last_sync_at:               finished,
        status:                     "connected",
        error_message:              nil,
        last_sync_created_count:    created,
        last_sync_duplicate_count:  duplicated,
        last_sync_error_count:      errored,
        last_sync_duration_seconds: (finished - started).round
      )
      record_run!(started, finished, "success", created, duplicated, errored, nil)
      { created: created, duplicated: duplicated, errored: errored }
    rescue StandardError => e
      # Registra o run falho no histórico (RF21.7) e propaga — o SyncJob trata
      # o status da conexão (expired/error) a partir da exceção.
      record_run!(started, Time.current, "error", created, duplicated, errored, e.message)
      raise
    end

    private

    # Uma linha por execução de sync (RF21.7 — histórico das últimas N).
    def record_run!(started, finished, status, created, duplicated, errored, error_message)
      @connection.syncs.create!(
        started_at:       started,
        finished_at:      finished,
        duration_seconds: (finished - started).round,
        status:           status,
        created_count:    created,
        duplicate_count:  duplicated,
        error_count:      errored,
        error_message:    error_message
      )
    end

    # :created | :duplicated | :errored. Unicidade é garantida no DB
    # (external_transaction_id gerado); capturamos a violação pra contar como
    # duplicado sem abortar o sync. Erros de dado isolados (ex.: data
    # malformada) contam como :errored e não derrubam o lote.
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
      :created
    rescue ActiveRecord::RecordNotUnique
      :duplicated
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Sync] transação ignorada (#{t[:id]}): #{e.message}")
      :errored
    end

    def default_provider
      BankAggregators::Pluggy.new(
        client_id:     ENV.fetch("PLUGGY_CLIENT_ID"),
        client_secret: ENV.fetch("PLUGGY_CLIENT_SECRET")
      )
    end
  end
end
