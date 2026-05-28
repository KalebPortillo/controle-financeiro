require "test_helper"

class BankConnections::SyncJobTest < ActiveJob::TestCase
  def connection_with_account
    conn = create(:bank_connection, status: "connected")
    create(:account, workspace: conn.workspace, bank_connection: conn, external_id: "acc-1")
    conn
  end

  def stub_auth
    stub_request(:post, "https://api.pluggy.ai/auth")
      .to_return(status: 200, body: { apiKey: "k" }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  test "roda o sync e deixa a conexão como connected" do
    conn = connection_with_account
    stub_auth
    stub_request(:get, %r{https://api\.pluggy\.ai/transactions})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { results: [
                   { id: "t1", amount: -30.0, currencyCode: "BRL", date: "2026-02-01", description: "X" }
                 ] }.to_json)

    assert_difference -> { Transaction.count }, 1 do
      BankConnections::SyncJob.perform_now(conn.id)
    end
    assert_equal "connected", conn.reload.status
  end

  test "marca expired e re-levanta em ItemError" do
    conn = connection_with_account
    stub_auth
    stub_request(:get, %r{https://api\.pluggy\.ai/transactions})
      .to_return(status: 403, body: '{"message":"item login error"}',
                 headers: { "Content-Type" => "application/json" })

    assert_raises(BankAggregators::ItemError) do
      BankConnections::SyncJob.perform_now(conn.id)
    end
    assert_equal "expired", conn.reload.status
  end
end
