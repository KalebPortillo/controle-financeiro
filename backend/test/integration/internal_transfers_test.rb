require "test_helper"

# RF11 — endpoints de transferências internas: listar, marcar, desmarcar.
class InternalTransfersTest < ActionDispatch::IntegrationTest
  setup do
    @user      = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
    @acc_a = create(:account, workspace: @workspace)
    @acc_b = create(:account, workspace: @workspace)
    @debit  = create(:transaction, workspace: @workspace, account: @acc_a,
                     direction: "debit", amount_cents: 50_000, status: "consolidated")
    @credit = create(:transaction, workspace: @workspace, account: @acc_b,
                     direction: "credit", amount_cents: 50_000, status: "consolidated")
  end

  test "GET index lists the workspace transfers" do
    create(:internal_transfer, workspace: @workspace,
           debit_transaction: @debit, credit_transaction: @credit)
    get "/api/v1/internal_transfers"
    assert_response :ok
    body = JSON.parse(response.body)["internal_transfers"]
    assert_equal 1, body.size
    assert_equal @debit.id, body.first["debit"]["id"]
  end

  test "GET index requires auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/internal_transfers"
    assert_response :unauthorized
  end

  test "POST marks a transfer manually (confirmed_by set)" do
    assert_difference -> { InternalTransfer.count }, 1 do
      post "/api/v1/internal_transfers",
           params: { debit_transaction_id: @debit.id, credit_transaction_id: @credit.id }, as: :json
    end
    assert_response :created
    body = JSON.parse(response.body)["internal_transfer"]
    assert_equal true, body["manual"]
  end

  test "POST 422 when directions are wrong" do
    post "/api/v1/internal_transfers",
         params: { debit_transaction_id: @credit.id, credit_transaction_id: @debit.id }, as: :json
    assert_response :unprocessable_entity
  end

  test "POST 404 for a transaction of another workspace" do
    foreign = create(:transaction, workspace: create(:workspace), account: create(:account), direction: "credit")
    post "/api/v1/internal_transfers",
         params: { debit_transaction_id: @debit.id, credit_transaction_id: foreign.id }, as: :json
    assert_response :not_found
  end

  test "DELETE unmarks a transfer" do
    transfer = create(:internal_transfer, workspace: @workspace,
                      debit_transaction: @debit, credit_transaction: @credit)
    assert_difference -> { InternalTransfer.count }, -1 do
      delete "/api/v1/internal_transfers/#{transfer.id}"
    end
    assert_response :no_content
  end

  test "DELETE 404 cross-workspace" do
    other = create(:workspace)
    d = create(:transaction, workspace: other, account: create(:account, workspace: other), direction: "debit")
    c = create(:transaction, workspace: other, account: create(:account, workspace: other), direction: "credit")
    transfer = create(:internal_transfer, workspace: other, debit_transaction: d, credit_transaction: c)
    delete "/api/v1/internal_transfers/#{transfer.id}"
    assert_response :not_found
  end
end
