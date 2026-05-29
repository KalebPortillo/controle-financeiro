require "test_helper"

# RF2 — inbox: listagem das transações pendentes (e leitura geral por status).
class TransactionsInboxTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
    @account    = create(:account, workspace: @workspace, owner_membership: @membership)
  end

  def txn(**attrs)
    create(:transaction, **{ workspace: @workspace, account: @account }.merge(attrs))
  end

  test "lista pendentes por default, escopado no workspace, com pending_count" do
    p1 = txn(status: "pending", original_description: "Padaria")
    txn(status: "consolidated")
    other = create(:workspace)
    create(:transaction, workspace: other, account: create(:account, workspace: other))

    get "/api/v1/transactions"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 1, body["transactions"].size
    assert_equal p1.id, body["transactions"].first["id"]
    assert_equal 1, body["pending_count"]
  end

  test "exige auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/transactions"
    assert_response :unauthorized
  end

  test "filtra por status explícito" do
    txn(status: "pending")
    txn(status: "consolidated")
    get "/api/v1/transactions?status=consolidated"
    body = JSON.parse(response.body)
    assert_equal 1, body["transactions"].size
    assert_equal "consolidated", body["transactions"].first["status"]
  end

  test "filtra por q (descrição/título, case-insensitive)" do
    txn(status: "pending", original_description: "IFOOD *RESTAURANTE")
    txn(status: "pending", original_description: "UBER TRIP")
    get "/api/v1/transactions?q=ifood"
    assert_equal 1, JSON.parse(response.body)["transactions"].size
  end

  test "filtra por direction e account_id" do
    txn(status: "pending", direction: "debit")
    txn(status: "pending", direction: "credit")
    get "/api/v1/transactions?direction=credit"
    assert_equal 1, JSON.parse(response.body)["transactions"].size

    other_account = create(:account, workspace: @workspace, owner_membership: @membership)
    txn(status: "pending", account: other_account)
    get "/api/v1/transactions?account_id=#{other_account.id}"
    assert_equal 1, JSON.parse(response.body)["transactions"].size
  end

  test "filtra consolidados por período (from/to) — RF4" do
    txn(status: "consolidated", occurred_at: Date.new(2026, 4, 10))
    in_may = txn(status: "consolidated", occurred_at: Date.new(2026, 5, 15))
    txn(status: "consolidated", occurred_at: Date.new(2026, 6, 2))

    get "/api/v1/transactions?status=consolidated&from=2026-05-01&to=2026-05-31"
    body = JSON.parse(response.body)
    assert_equal 1, body["transactions"].size
    assert_equal in_may.id, body["transactions"].first["id"]
  end

  test "ordena por -occurred_at (mais recente primeiro)" do
    older = txn(status: "pending", occurred_at: Date.new(2026, 1, 1))
    newer = txn(status: "pending", occurred_at: Date.new(2026, 5, 1))
    get "/api/v1/transactions"
    ids = JSON.parse(response.body)["transactions"].map { |t| t["id"] }
    assert_equal [ newer.id, older.id ], ids
  end
end
