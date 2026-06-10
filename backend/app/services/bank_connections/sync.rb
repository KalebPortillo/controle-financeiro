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

    # Transações por lote enviado à IA (P3). Com batching há poucos jobs e cada
    # um classifica até SUGGEST_BATCH_SIZE numa única chamada ao Gemini.
    SUGGEST_BATCH_SIZE = 25

    def call
      created = 0
      duplicated = 0
      errored = 0
      started = Time.current
      @suggest_ids = []

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

      # IA em lote (P3): fora do onboarding, enfileira BatchSuggestJob em fatias
      # de SUGGEST_BATCH_SIZE — poucas chamadas ao Gemini em vez de 1 por tx.
      # RF22/F2: o sync NÃO inicia mais a análise IA do onboarding. Ela é
      # disparada pelo usuário (clique em "Continuar" → advance para analyzing),
      # pra desacoplar a análise do sync e não prender o passo de análise.
      dispatch_suggestions

      # RF9.1: detecção de recorrentes ao fim do sync (fora do onboarding).
      maybe_kickoff_recurrence_detection

      # RF17: avisa que chegaram gastos novos na inbox (fora do onboarding).
      notify_new_inbox_items(created)

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

    # Fora do onboarding, enfileira a análise IA em lotes (P3). Durante o
    # onboarding a IA roda em batch único pelo AnalyzeJob, disparado pelo usuário.
    def dispatch_suggestions
      return if @suggest_ids.empty?
      return if onboarding_in_progress?(@connection.workspace)

      @suggest_ids.each_slice(SUGGEST_BATCH_SIZE) do |ids|
        AiSuggestion::BatchSuggestJob.perform_later(ids)
      end
    end

    # Fora do onboarding, dispara as detecções sobre o histórico consolidado do
    # workspace: recorrentes (RF9.1) e transferências internas (RF11.1). Ambas
    # idempotentes (ver os respectivos services).
    def maybe_kickoff_recurrence_detection
      ws = @connection.workspace
      return if onboarding_in_progress?(ws)

      Recurrences::DetectJob.perform_later(ws.id)
      InternalTransfers::DetectJob.perform_later(ws.id)
    end

    # Cada sync com novidades é um evento legítimo — sem dedup. Durante o
    # onboarding o usuário já está olhando o fluxo, notificar seria ruído.
    def notify_new_inbox_items(created)
      return if created.zero?
      return if onboarding_in_progress?(@connection.workspace)

      institution = @connection.accounts.first&.institution
      Notifications::Create.call(
        workspace: @connection.workspace,
        kind:      "inbox_new",
        payload:   {
          "count"              => created,
          "bank_connection_id" => @connection.id,
          "institution_label"  => BankConnections::Serializer::INSTITUTION_LABELS[institution] || "banco"
        }
      )
    end

    # :created | :duplicated | :errored. Unicidade é garantida no DB
    # (external_transaction_id gerado); capturamos a violação pra contar como
    # duplicado sem abortar o sync. Erros de dado isolados (ex.: data
    # malformada) contam como :errored e não derrubam o lote.
    def import_transaction(account, t)
      amount = t.fetch(:amount).to_f
      installment = Transactions::Installment.parse(raw: t[:raw], description: t[:description])
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
        source_metadata:      t[:raw] || { "id" => t[:id] },
        installment_number:   installment&.number,
        installment_total:    installment&.total,
        installment_group_id: installment && Transactions::Installment.group_id(
          account_id: account.id, description: t[:description], total: installment.total
        )
      )
      @suggest_ids << tx.id
      :created
    rescue ActiveRecord::RecordNotUnique
      :duplicated
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Sync] transação ignorada (#{t[:id]}): #{e.message}")
      :errored
    end

    ONBOARDING_ACTIVE_STATUSES = %w[connecting analyzing tagging].freeze

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
