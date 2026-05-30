require "test_helper"

# RF9.5 — endpoint de faturas do cartão (derivadas).
class InvoicesTest < ActionDispatch::IntegrationTest
  setup do
    @user      = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
    @card      = create(:account, workspace: @workspace, kind: "credit_card")
  end

  test "GET /accounts/:id/invoices retorna a fatura aberta por default" do
    create(:transaction, workspace: @workspace, account: @card, direction: "debit",
           amount_cents: 3000, occurred_at: Date.current, status: "pending",
           original_description: "PADARIA")

    get "/api/v1/accounts/#{@card.id}/invoices"
    assert_response :ok
    invoices = JSON.parse(response.body)["invoices"]
    assert_equal 1, invoices.size
    assert_equal "open", invoices.first["status"]
    assert_equal @card.id, invoices.first["account_id"]
  end

  test "GET /accounts/:id/invoices?status=future retorna os próximos meses" do
    get "/api/v1/accounts/#{@card.id}/invoices?status=future"
    assert_response :ok
    assert_equal 3, JSON.parse(response.body)["invoices"].size
  end

  test "conta que não é cartão → 422" do
    checking = create(:account, workspace: @workspace, kind: "checking")
    get "/api/v1/accounts/#{checking.id}/invoices"
    assert_response :unprocessable_entity
  end

  test "conta de outro workspace → 404" do
    foreign = create(:account, workspace: create(:workspace), kind: "credit_card")
    get "/api/v1/accounts/#{foreign.id}/invoices"
    assert_response :not_found
  end

  test "exige auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/accounts/#{@card.id}/invoices"
    assert_response :unauthorized
  end
end
