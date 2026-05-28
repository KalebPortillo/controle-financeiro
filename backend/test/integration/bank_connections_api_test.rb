require "test_helper"

class BankConnectionsApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    # test_sign_in cria user + workspace pessoal; pegamos a membership dele.
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace

    # Stubs Pluggy (webmock) — não tocamos a API real em integration.
    stub_request(:post, "https://api.pluggy.ai/auth")
      .to_return(status: 200, body: { apiKey: "fake-jwt" }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  # --- connect_token ----------------------------------------------------

  test "POST /bank_connections/connect_token devolve token do widget" do
    stub_request(:post, "https://api.pluggy.ai/connect_token")
      .to_return(status: 200, body: { accessToken: "connect-tok-123" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    post "/api/v1/bank_connections/connect_token", as: :json
    assert_response :ok
    assert_equal "connect-tok-123", JSON.parse(response.body)["connect_token"]
  end

  test "POST /bank_connections/connect_token exige autenticação" do
    delete "/api/v1/sessions/current"
    post "/api/v1/bank_connections/connect_token", as: :json
    assert_response :unauthorized
  end

  # --- create -----------------------------------------------------------

  test "POST /bank_connections persiste conexão + accounts do item" do
    stub_request(:get, %r{https://api\.pluggy\.ai/items/item-abc})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: "item-abc", status: "UPDATED",
                         connector: { id: 612, name: "Nubank" } }.to_json)
    stub_request(:get, %r{https://api\.pluggy\.ai/accounts})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { results: [
                   { id: "a1", type: "BANK",   name: "Conta", balance: 100, currencyCode: "BRL" },
                   { id: "a2", type: "CREDIT", name: "Cartão", balance: -20, currencyCode: "BRL" }
                 ] }.to_json)

    assert_difference -> { BankConnection.count }, 1 do
      assert_difference -> { Account.count }, 2 do
        post "/api/v1/bank_connections",
             params: { item_id: "item-abc", history_since: "2026-01-01" }, as: :json
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    accounts = body.dig("bank_connection", "accounts")
    assert_equal 2, accounts.size
    assert_equal "connected", body.dig("bank_connection", "status")
    assert_equal [ "Nubank" ], accounts.map { |a| a["institution_label"] }.uniq
    assert_equal %w[checking credit_card].sort, accounts.map { |a| a["kind"] }.sort
  end

  test "POST /bank_connections exige autenticação" do
    delete "/api/v1/sessions/current"
    post "/api/v1/bank_connections",
         params: { item_id: "x", history_since: "2026-01-01" }, as: :json
    assert_response :unauthorized
  end

  test "POST /bank_connections sem item_id retorna 422" do
    post "/api/v1/bank_connections", params: { history_since: "2026-01-01" }, as: :json
    assert_response :unprocessable_entity
  end
end
