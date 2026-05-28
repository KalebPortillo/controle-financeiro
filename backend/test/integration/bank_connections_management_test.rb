require "test_helper"

# RF21 — gestão/listagem de conexões. Separado do bank_connections_api_test
# (que cobre connect_token + create) pra manter os arquivos focados.
class BankConnectionsManagementTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
  end

  def connection(**attrs)
    create(:bank_connection, { workspace: @workspace, owner_membership: @membership }.merge(attrs))
  end

  # --- index (RF21) -----------------------------------------------------

  test "GET /bank_connections lista as conexões do workspace com summary" do
    c1 = connection(status: "connected", last_sync_created_count: 5)
    create(:account, workspace: @workspace, bank_connection: c1, owner_membership: @membership, kind: "checking")
    connection(status: "error", error_message: "boom")
    # conexão de outro workspace não deve aparecer
    connection(workspace: create(:workspace))

    get "/api/v1/bank_connections"
    assert_response :ok
    body = JSON.parse(response.body)

    assert_equal 2, body["connections"].size
    summary = body["summary"]
    assert_equal 2, summary["total"]
    assert_equal 1, summary["connected"]
    assert_equal 1, summary["error"]

    enriched = body["connections"].find { |c| c["id"] == c1.id }
    assert_equal "connected", enriched["status"]
    assert_equal 5, enriched["last_sync_created_count"]
    assert_equal 1, enriched["accounts"].size
  end

  test "GET /bank_connections exige auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/bank_connections"
    assert_response :unauthorized
  end

  # --- show -------------------------------------------------------------

  test "GET /bank_connections/:id devolve a conexão" do
    c = connection
    get "/api/v1/bank_connections/#{c.id}"
    assert_response :ok
    assert_equal c.id, JSON.parse(response.body).dig("bank_connection", "id")
  end

  test "GET /bank_connections/:id de outro workspace → 404" do
    other = connection(workspace: create(:workspace))
    get "/api/v1/bank_connections/#{other.id}"
    assert_response :not_found
  end

  # --- sync (force) -----------------------------------------------------

  test "POST /bank_connections/:id/sync enfileira job e marca syncing (202)" do
    c = connection(status: "connected")
    assert_enqueued_with(job: BankConnections::SyncJob, args: [ c.id ]) do
      post "/api/v1/bank_connections/#{c.id}/sync"
    end
    assert_response :accepted
    assert_equal "syncing", c.reload.status
  end

  # --- sync_all ---------------------------------------------------------

  test "POST /bank_connections/sync_all enfileira todas as conexões" do
    a = connection
    b = connection
    assert_enqueued_jobs 2, only: BankConnections::SyncJob do
      post "/api/v1/bank_connections/sync_all"
    end
    assert_response :accepted
    assert_equal "syncing", a.reload.status
    assert_equal "syncing", b.reload.status
  end

  # --- reconnect --------------------------------------------------------

  test "POST /bank_connections/:id/reconnect devolve connect_token do item" do
    c = connection(external_connection_id: "item-rc")
    stub_request(:post, "https://api.pluggy.ai/auth")
      .to_return(status: 200, body: { apiKey: "k" }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, "https://api.pluggy.ai/connect_token")
      .with(body: hash_including("itemId" => "item-rc"))
      .to_return(status: 200, body: { accessToken: "rc-tok" }.to_json, headers: { "Content-Type" => "application/json" })

    post "/api/v1/bank_connections/#{c.id}/reconnect"
    assert_response :ok
    assert_equal "rc-tok", JSON.parse(response.body)["connect_token"]
  end

  # --- destroy ----------------------------------------------------------

  test "DELETE /bank_connections/:id remove a conexão" do
    c = connection
    assert_difference -> { BankConnection.count }, -1 do
      delete "/api/v1/bank_connections/#{c.id}"
    end
    assert_response :no_content
  end

  test "DELETE /bank_connections/:id de outro workspace → 404" do
    other = connection(workspace: create(:workspace))
    delete "/api/v1/bank_connections/#{other.id}"
    assert_response :not_found
    assert BankConnection.exists?(other.id)
  end
end
