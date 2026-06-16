require "test_helper"

class BankConnections::SyncTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Fake provider — só precisa de list_transactions pro sync.
  class FakeProvider
    def initialize(by_account:)
      @by_account = by_account
    end

    def list_transactions(account_id:, from:, to: nil)
      @by_account.fetch(account_id, [])
    end
  end

  def setup_connection_with_account(institution: "nubank", kind: "checking")
    connection = create(:bank_connection, sync_history_since: Date.new(2026, 1, 1))
    account = create(:account,
                     workspace: connection.workspace,
                     bank_connection: connection,
                     institution: institution,
                     kind: kind,
                     external_id: "acc-1")
    [ connection, account ]
  end

  def txn(id, amount, desc, date: "2026-03-10", type: nil)
    {
      id: id, amount: amount, currency_code: "BRL", type: type,
      date: date, description: desc,
      raw: { "id" => id, "amount" => amount, "type" => type }
    }
  end

  test "cria transactions pending na inbox a partir do provider" do
    connection, account = setup_connection_with_account
    provider = FakeProvider.new(by_account: {
      "acc-1" => [
        txn("tx-1", -50.0, "Padaria"),   # débito (Pluggy: negativo = saída)
        txn("tx-2", 1200.0, "Salário")   # crédito
      ]
    })

    assert_difference -> { Transaction.count }, 2 do
      BankConnections::Sync.call(connection: connection, provider: provider)
    end

    t1 = account.transactions.find_by!(external_transaction_id: "tx-1")
    assert_equal "pending",        t1.status
    assert_equal "automatic_sync", t1.source
    assert_equal "debit",          t1.direction
    assert_equal 5000,             t1.amount_cents   # |−50.00| em centavos
    assert_equal "Padaria",        t1.original_description
    assert_equal Date.new(2026, 3, 10), t1.occurred_at

    t2 = account.transactions.find_by!(external_transaction_id: "tx-2")
    assert_equal "credit", t2.direction
    assert_equal 120000,   t2.amount_cents
  end

  # Regressão do bug crítico: gastos de cartão apareciam como receita (+).
  # Em banco REAL (Nubank) o `type` do Pluggy é a direção do dinheiro e é
  # canônico: compra de cartão vem type=DEBIT com amount POSITIVO (o sinal
  # sozinho classificaria errado), estorno/pagamento vem type=CREDIT negativo.
  test "instituição real: direção vem do `type` do Pluggy (cartão)" do
    connection, account = setup_connection_with_account(institution: "nubank", kind: "credit_card")
    provider = FakeProvider.new(by_account: {
      "acc-1" => [
        txn("cc-buy", 250.0, "Amazon 3/10",       type: "DEBIT"),  # compra → gasto
        txn("cc-ref", -88.0, "Estorno de compra", type: "CREDIT")  # estorno → entrada
      ]
    })

    BankConnections::Sync.call(connection: connection, provider: provider)

    purchase = account.transactions.find_by!(external_transaction_id: "cc-buy")
    assert_equal "debit", purchase.direction, "compra de cartão (type DEBIT, amount+) deve ser débito"
    assert_equal 25000,   purchase.amount_cents

    refund = account.transactions.find_by!(external_transaction_id: "cc-ref")
    assert_equal "credit", refund.direction
    assert_equal 8800,     refund.amount_cents
  end

  # O conector SANDBOX do Pluggy reporta o `type` do cartão INVERTIDO (compra
  # vem como CREDIT, amount negativo). Ali o sinal do amount é o confiável.
  test "conector sandbox: direção vem do sinal do amount (type vem invertido)" do
    connection, account = setup_connection_with_account(institution: "sandbox", kind: "credit_card")
    provider = FakeProvider.new(by_account: {
      "acc-1" => [
        txn("sb-buy", -55.9, "NETFLIX.COM", type: "CREDIT"), # compra (sandbox inverte o type)
        txn("sb-in",  120.0, "Entrada",     type: "DEBIT")
      ]
    })

    BankConnections::Sync.call(connection: connection, provider: provider)

    purchase = account.transactions.find_by!(external_transaction_id: "sb-buy")
    assert_equal "debit", purchase.direction, "no sandbox o amount negativo manda — é gasto"
    assert_equal 5590,    purchase.amount_cents

    entrada = account.transactions.find_by!(external_transaction_id: "sb-in")
    assert_equal "credit", entrada.direction
  end

  test "sem `type` (ex.: import sem o campo) cai no sinal do amount" do
    connection, account = setup_connection_with_account
    provider = FakeProvider.new(by_account: {
      "acc-1" => [ txn("nt-1", -80.0, "Sem type", type: nil) ]
    })

    BankConnections::Sync.call(connection: connection, provider: provider)

    t = account.transactions.find_by!(external_transaction_id: "nt-1")
    assert_equal "debit", t.direction
  end

  test "é idempotente — re-sync não duplica transações já importadas" do
    connection, _account = setup_connection_with_account
    provider = FakeProvider.new(by_account: {
      "acc-1" => [ txn("tx-1", -50.0, "Padaria") ]
    })

    BankConnections::Sync.call(connection: connection, provider: provider)
    assert_no_difference -> { Transaction.count } do
      BankConnections::Sync.call(connection: connection, provider: provider)
    end
  end

  test "atualiza last_sync_at e status connected ao terminar" do
    connection, _ = setup_connection_with_account
    provider = FakeProvider.new(by_account: { "acc-1" => [] })

    freeze_time do
      BankConnections::Sync.call(connection: connection, provider: provider)
      assert_equal Time.current.to_i, connection.reload.last_sync_at.to_i
      assert_equal "connected", connection.status
    end
  end

  test "retorna contagem de criados/duplicados" do
    connection, _ = setup_connection_with_account
    provider = FakeProvider.new(by_account: {
      "acc-1" => [ txn("tx-1", -10.0, "A"), txn("tx-2", -20.0, "B") ]
    })

    result = BankConnections::Sync.call(connection: connection, provider: provider)
    assert_equal 2, result[:created]
    assert_equal 0, result[:duplicated]

    result2 = BankConnections::Sync.call(connection: connection, provider: provider)
    assert_equal 0, result2[:created]
    assert_equal 2, result2[:duplicated]
  end

  # Provider que estoura ao listar — simula token expirado / falha de rede.
  class FailingProvider
    def list_transactions(**)
      raise BankAggregators::Error, "falha no provider"
    end
  end

  test "grava um BankConnectionSync de sucesso com contadores (RF21.7)" do
    connection, _ = setup_connection_with_account
    provider = FakeProvider.new(by_account: {
      "acc-1" => [ txn("tx-1", -10.0, "A"), txn("tx-2", -20.0, "B") ]
    })

    assert_difference -> { connection.syncs.count }, 1 do
      BankConnections::Sync.call(connection: connection, provider: provider)
    end

    run = connection.syncs.recent.first
    assert_equal "success", run.status
    assert_equal 2, run.created_count
    assert_equal 0, run.duplicate_count
    assert_not_nil run.started_at
    assert_not_nil run.finished_at
    assert_not_nil run.duration_seconds
  end

  test "grava um BankConnectionSync de erro e re-levanta quando o provider falha" do
    connection, _ = setup_connection_with_account

    assert_difference -> { connection.syncs.count }, 1 do
      assert_raises(BankAggregators::Error) do
        BankConnections::Sync.call(connection: connection, provider: FailingProvider.new)
      end
    end

    run = connection.syncs.recent.first
    assert_equal "error", run.status
    assert_equal "falha no provider", run.error_message
  end

  # RF9.4 — parcelamento: ingestão popula installment_number/total/group_id.
  test "popula campos de parcelamento a partir do creditCardMetadata" do
    connection, account = setup_connection_with_account
    parcela = txn("tx-p1", -50.0, "GELADEIRA").merge(
      raw: { "id" => "tx-p1", "creditCardMetadata" => { "installmentNumber" => 3, "totalInstallments" => 12 } }
    )
    provider = FakeProvider.new(by_account: { "acc-1" => [ parcela ] })

    BankConnections::Sync.call(connection: connection, provider: provider)
    t = account.transactions.find_by!(external_transaction_id: "tx-p1")
    assert_equal 3,  t.installment_number
    assert_equal 12, t.installment_total
    assert_not_nil t.installment_group_id
  end

  test "parcelas da mesma compra compartilham installment_group_id" do
    connection, account = setup_connection_with_account
    p3 = txn("tx-p3", -50.0, "GELADEIRA 3/12", date: "2026-03-10")
    p4 = txn("tx-p4", -50.0, "GELADEIRA 4/12", date: "2026-04-10")
    provider = FakeProvider.new(by_account: { "acc-1" => [ p3, p4 ] })

    BankConnections::Sync.call(connection: connection, provider: provider)
    g3 = account.transactions.find_by!(external_transaction_id: "tx-p3").installment_group_id
    g4 = account.transactions.find_by!(external_transaction_id: "tx-p4").installment_group_id
    assert_equal g3, g4
  end

  test "não importa parcela projetada quando já existe a canônica (anti-duplicata)" do
    connection, account = setup_connection_with_account(kind: "credit_card")
    # Canônica (compra real, com purchaseDate real + MCC) já no banco.
    create(:transaction, account: account, workspace: account.workspace,
           original_description: "Mercadolivre 3/4", installment_number: 3, installment_total: 4,
           occurred_at: Date.new(2026, 7, 30), status: "pending",
           source_metadata: { "id" => "real-3", "creditCardMetadata" => {
             "purchaseDate" => "2026-05-30T03:05:01.001Z", "payeeMCC" => 5999,
             "installmentNumber" => 3, "totalInstallments" => 4 } })

    # Projetada: purchaseDate sintético (própria data, meia-noite), sem MCC, id próprio.
    projected = {
      id: "proj-3", amount: 26.95, currency_code: "BRL", type: "DEBIT",
      date: "2026-07-31", description: "Mercadolivre 3/4",
      raw: { "id" => "proj-3", "creditCardMetadata" => {
        "purchaseDate" => "2026-07-31T00:00:00.001Z",
        "installmentNumber" => 3, "totalInstallments" => 4 } }
    }
    provider = FakeProvider.new(by_account: { "acc-1" => [ projected ] })

    assert_no_difference -> { Transaction.count } do
      BankConnections::Sync.call(connection: connection, provider: provider)
    end
    assert_nil account.transactions.find_by(external_transaction_id: "proj-3")
  end

  test "transação à vista não recebe campos de parcelamento" do
    connection, account = setup_connection_with_account
    provider = FakeProvider.new(by_account: { "acc-1" => [ txn("tx-v", -50.0, "PADARIA") ] })

    BankConnections::Sync.call(connection: connection, provider: provider)
    t = account.transactions.find_by!(external_transaction_id: "tx-v")
    assert_nil t.installment_number
    assert_nil t.installment_total
    assert_nil t.installment_group_id
  end

  def sync_parcels(connection, *parcels)
    BankConnections::Sync.call(connection: connection,
                               provider: FakeProvider.new(by_account: { "acc-1" => parcels }))
  end

  test "parcela futura auto-consolida e herda título/tags quando há irmã consolidada (RF9.4.2)" do
    connection, account = setup_connection_with_account
    sync_parcels(connection, txn("tx-p1", -50.0, "GELADEIRA 1/12", date: "2026-03-10"))
    p1 = account.transactions.find_by!(external_transaction_id: "tx-p1")
    tag = create(:tag, workspace: connection.workspace, name: "Casa")
    p1.update!(status: "consolidated", consolidated_at: Time.current, improved_title: "Geladeira Brastemp")
    p1.tags = [ tag ]

    assert_no_enqueued_jobs(only: AiSuggestion::BatchSuggestJob) do
      sync_parcels(connection, txn("tx-p2", -50.0, "GELADEIRA 2/12", date: "2026-04-10"))
    end

    p2 = account.transactions.find_by!(external_transaction_id: "tx-p2")
    assert_equal "consolidated", p2.status
    assert_equal "Geladeira Brastemp", p2.improved_title
    assert_equal "analyzed", p2.ai_status
    assert_equal [ "Casa" ], p2.tags.pluck(:name)
    assert_equal Date.new(2026, 4, 10), p2.occurred_at # cada parcela no seu mês
  end

  test "parcela futura fica pending e crua quando não há irmã consolidada nem título" do
    connection, account = setup_connection_with_account
    sync_parcels(connection, txn("tx-p1", -50.0, "GELADEIRA 1/12", date: "2026-03-10"))
    # p1 segue pending sem título (IA não rodou em test)

    sync_parcels(connection, txn("tx-p2", -50.0, "GELADEIRA 2/12", date: "2026-04-10"))
    p2 = account.transactions.find_by!(external_transaction_id: "tx-p2")
    assert_equal "pending", p2.status
    assert_nil p2.improved_title
  end

  test "parcela futura herda título e pula IA quando a irmã pending já tem título" do
    connection, account = setup_connection_with_account
    sync_parcels(connection, txn("tx-p1", -50.0, "GELADEIRA 1/12", date: "2026-03-10"))
    account.transactions.find_by!(external_transaction_id: "tx-p1").update!(improved_title: "Geladeira")

    assert_no_enqueued_jobs(only: AiSuggestion::BatchSuggestJob) do
      sync_parcels(connection, txn("tx-p2", -50.0, "GELADEIRA 2/12", date: "2026-04-10"))
    end

    p2 = account.transactions.find_by!(external_transaction_id: "tx-p2")
    assert_equal "pending", p2.status
    assert_equal "Geladeira", p2.improved_title
    assert_equal "analyzed", p2.ai_status
  end

  test "sync com transações novas emite inbox_new com a contagem (RF17)" do
    connection, _account = setup_connection_with_account
    provider = FakeProvider.new(by_account: {
      "acc-1" => [ txn("tx-1", -50.0, "Padaria"), txn("tx-2", -30.0, "Uber") ]
    })

    scope = -> { connection.workspace.notifications.where(kind: "inbox_new") }
    assert_difference -> { scope.call.count }, 1 do
      BankConnections::Sync.call(connection: connection, provider: provider)
    end

    n = scope.call.last
    assert_equal 2, n.payload["count"]
    assert_equal connection.id, n.payload["bank_connection_id"]
  end

  test "sync sem transações novas não emite inbox_new" do
    connection, _account = setup_connection_with_account
    provider = FakeProvider.new(by_account: { "acc-1" => [ txn("tx-1", -50.0, "Padaria") ] })
    BankConnections::Sync.call(connection: connection, provider: provider)

    # Re-sync: tudo duplicado, created = 0.
    assert_no_difference -> { Notification.where(kind: "inbox_new").count } do
      BankConnections::Sync.call(connection: connection, provider: provider)
    end
  end

  test "durante o onboarding não emite inbox_new" do
    connection, _account = setup_connection_with_account
    connection.workspace.update!(onboarding_state: { "status" => "connecting" })
    provider = FakeProvider.new(by_account: { "acc-1" => [ txn("tx-1", -50.0, "Padaria") ] })

    assert_no_difference -> { Notification.where(kind: "inbox_new").count } do
      BankConnections::Sync.call(connection: connection, provider: provider)
    end
  end

  def many_txns(count)
    (1..count).map { |i| txn("tx-#{i}", -(10.0 + i), "Gasto #{i}") }
  end

  test "com Telegram vinculado: botões por tx, nunca resumo no Telegram (lote pequeno)" do
    connection, _account = setup_connection_with_account
    connection.workspace.update!(telegram_chat_id: -100, telegram_linked_at: Time.current)
    provider = FakeProvider.new(by_account: { "acc-1" => many_txns(3) })

    assert_enqueued_with(job: Notifications::TelegramInboxButtonsJob) do
      assert_no_enqueued_jobs(only: Notifications::TelegramDeliveryJob) do
        BankConnections::Sync.call(connection: connection, provider: provider)
      end
    end
    # in-app continua: o sininho ainda recebe o resumo.
    assert_equal 1, connection.workspace.notifications.where(kind: "inbox_new").count
  end

  test "lote grande também vai como botões (últimas 7 + link), nunca resumo no Telegram" do
    connection, _account = setup_connection_with_account
    connection.workspace.update!(telegram_chat_id: -100, telegram_linked_at: Time.current)
    provider = FakeProvider.new(by_account: { "acc-1" => many_txns(12) })

    assert_enqueued_with(job: Notifications::TelegramInboxButtonsJob) do
      assert_no_enqueued_jobs(only: Notifications::TelegramDeliveryJob) do
        BankConnections::Sync.call(connection: connection, provider: provider)
      end
    end
    assert_equal 1, connection.workspace.notifications.where(kind: "inbox_new").count
  end

  test "lote pequeno sem Telegram vinculado: só in-app, nenhum job de Telegram" do
    connection, _account = setup_connection_with_account
    provider = FakeProvider.new(by_account: { "acc-1" => many_txns(3) })

    assert_no_enqueued_jobs(only: [ Notifications::TelegramInboxButtonsJob, Notifications::TelegramDeliveryJob ]) do
      BankConnections::Sync.call(connection: connection, provider: provider)
    end
    assert_equal 1, connection.workspace.notifications.where(kind: "inbox_new").count
  end
end
