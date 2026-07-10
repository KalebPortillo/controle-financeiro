require "test_helper"

class BankConnections::PruneTransactionsTest < ActiveSupport::TestCase
  def setup_conn
    connection = create(:bank_connection)
    account = create(:account, workspace: connection.workspace,
                               bank_connection: connection, external_id: "acc-1")
    [ connection, account ]
  end

  def synced(account, ext_id, status: "pending")
    create(:transaction, account: account, workspace: account.workspace,
                         status: status, source: "automatic_sync",
                         source_metadata: { "id" => ext_id })
  end

  test "remove as pendentes cujos ids vieram no transactions/deleted" do
    connection, account = setup_conn
    keep = synced(account, "keep")
    gone = synced(account, "gone")

    removed = BankConnections::PruneTransactions.call(connection: connection, external_ids: [ "gone" ])

    assert_equal 1, removed
    assert Transaction.exists?(keep.id)
    assert_not Transaction.exists?(gone.id)
  end

  test "não remove transação já consolidada/rejeitada (decisão humana)" do
    connection, account = setup_conn
    consolidated = synced(account, "c", status: "consolidated")

    assert_no_difference -> { Transaction.count } do
      BankConnections::PruneTransactions.call(connection: connection, external_ids: [ "c" ])
    end
    assert Transaction.exists?(consolidated.id)
  end

  test "não toca em transações de outra conexão" do
    connection, account = setup_conn
    _other_conn = create(:bank_connection)
    other_account = create(:account, workspace: _other_conn.workspace,
                                     bank_connection: _other_conn, external_id: "acc-x")
    other = synced(other_account, "gone")

    BankConnections::PruneTransactions.call(connection: connection, external_ids: [ "gone" ])

    assert Transaction.exists?(other.id)
  end

  test "lista vazia é no-op" do
    connection, _ = setup_conn
    assert_equal 0, BankConnections::PruneTransactions.call(connection: connection, external_ids: [])
  end
end
