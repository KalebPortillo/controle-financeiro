require "test_helper"

class BankConnections::SyncTest < ActiveSupport::TestCase
  # Fake provider — só precisa de list_transactions pro sync.
  class FakeProvider
    def initialize(by_account:)
      @by_account = by_account
    end

    def list_transactions(account_id:, from:, to: nil)
      @by_account.fetch(account_id, [])
    end
  end

  def setup_connection_with_account
    connection = create(:bank_connection, sync_history_since: Date.new(2026, 1, 1))
    account = create(:account,
                     workspace: connection.workspace,
                     bank_connection: connection,
                     external_id: "acc-1")
    [ connection, account ]
  end

  def txn(id, amount, desc, date: "2026-03-10", direction_amount: nil)
    {
      id: id, amount: amount, currency_code: "BRL",
      date: date, description: desc, raw: { "id" => id, "amount" => amount }
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
end
