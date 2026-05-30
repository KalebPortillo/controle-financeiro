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
      # Grava o histórico ANTES do update! — o update! dispara o broadcast
      # (after_update_commit) que faz o frontend refetchar o histórico; se a
      # linha não existisse ainda, daria corrida e o painel veria o estado velho.
      record_run!(started, finished, "success", created, duplicated, errored, nil)
      @connection.update!(
        last_sync_at:               finished,
        status:                     "connected",
        error_message:              nil,
        last_sync_created_count:    created,
        last_sync_duplicate_count:  duplicated,
        last_sync_error_count:      errored,
        last_sync_duration_seconds: (finished - started).round
      )

      # RF22: encadear análise IA do onboarding quando aplicável.
      maybe_kickoff_onboarding_analysis
      # RF9.1: detecção de recorrentes ao fim do sync (fora do onboarding).
      maybe_kickoff_recurrence_detection

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

    # Quando o workspace está no fluxo de onboarding (RF22) e ainda em
    # connecting, transiciona pra analyzing + enfileira o AnalyzeJob.
    # Idempotente — se já avançou, o early-return cuida.
    def maybe_kickoff_onboarding_analysis
      ws = @connection.workspace
      state = ws.onboarding_state || {}
      return unless state["status"] == "connecting"

      Onboarding::Service.advance(ws, to: "analyzing")
      Onboarding::AnalyzeJob.perform_later(ws.id)
    end

    # Fora do onboarding, dispara a detecção de recorrentes (RF9.1) sobre o
    # histórico consolidado do workspace. Idempotente (ver Recurrences::Detect).
    def maybe_kickoff_recurrence_detection
      ws = @connection.workspace
      return if onboarding_in_progress?(ws)

      Recurrences::DetectJob.perform_later(ws.id)
    end

    # :created | :duplicated | :errored. Unicidade é garantida no DB
    # (external_transaction_id gerado); capturamos a violação pra contar como
    # duplicado sem abortar o sync. Erros de dado isolados (ex.: data
    # malformada) contam como :errored e não derrubam o lote.
    def import_transaction(account, t)
      amount = t.fetch(:amount).to_f
      tx = Transaction.create!(
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
      # RF22: durante o onboarding, NÃO disparamos o SuggestJob por tx —
      # a IA roda em batch (AnalyzeJob) no fim do sync inicial pra evitar
      # tags inconsistentes em modo onboarding um a um.
      AiSuggestion::SuggestJob.perform_later(tx.id) unless onboarding_in_progress?(account.workspace)
      :created
    rescue ActiveRecord::RecordNotUnique
      :duplicated
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Sync] transação ignorada (#{t[:id]}): #{e.message}")
      :errored
    end

    ONBOARDING_ACTIVE_STATUSES = %w[connecting analyzing tagging categorizing].freeze

    def onboarding_in_progress?(workspace)
      ONBOARDING_ACTIVE_STATUSES.include?(workspace.onboarding_state&.dig("status"))
    end

    def default_provider
      BankAggregators::Pluggy.new(
        client_id:     ENV.fetch("PLUGGY_CLIENT_ID"),
        client_secret: ENV.fetch("PLUGGY_CLIENT_SECRET")
      )
    end
  end
end
