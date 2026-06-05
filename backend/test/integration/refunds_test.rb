require "test_helper"

# RF10 — estornos: candidatos, vincular, desfazer.
class RefundsTest < ActionDispatch::IntegrationTest
  setup do
    @user      = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
    @account   = create(:account, workspace: @workspace)
    @debit  = create(:transaction, workspace: @workspace, account: @account,
                     direction: "debit", amount_cents: 10_000, status: "consolidated",
                     occurred_at: Date.current - 10)
    @credit = create(:transaction, workspace: @workspace, account: @account,
                     direction: "credit", amount_cents: 10_000, status: "pending",
                     occurred_at: Date.current)
  end

  test "GET refund_candidates lists compatible debits for a credit" do
    # ruído: valor muito diferente e gasto antigo demais não entram
    create(:transaction, workspace: @workspace, account: @account, direction: "debit",
           amount_cents: 999, status: "consolidated", occurred_at: Date.current - 5)
    get "/api/v1/transactions/#{@credit.id}/refund_candidates"
    assert_response :ok
    ids = JSON.parse(response.body)["refund_candidates"].map { |t| t["id"] }
    assert_includes ids, @debit.id
    assert_equal 1, ids.size
  end

  test "GET refund_candidates requires auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/transactions/#{@credit.id}/refund_candidates"
    assert_response :unauthorized
  end

  test "POST link_refund links the credit to the debit and discounts the effective amount" do
    assert_difference -> { TransactionRefund.count }, 1 do
      post "/api/v1/transactions/#{@credit.id}/link_refund",
           params: { refunded_transaction_id: @debit.id }, as: :json
    end
    assert_response :created
    assert_equal 0, @debit.reload.effective_amount_cents
  end

  test "POST link_refund 422 when :id is not a credit" do
    post "/api/v1/transactions/#{@debit.id}/link_refund",
         params: { refunded_transaction_id: @credit.id }, as: :json
    assert_response :unprocessable_entity
  end

  test "POST link_refund 404 for a debit of another workspace" do
    foreign = create(:transaction, workspace: create(:workspace), account: create(:account), direction: "debit")
    post "/api/v1/transactions/#{@credit.id}/link_refund",
         params: { refunded_transaction_id: foreign.id }, as: :json
    assert_response :not_found
  end

  test "DELETE transaction_refunds/:id undoes the link" do
    refund = create(:transaction_refund, refund_transaction: @credit,
                    refunded_transaction: @debit,
                    confirmed_by_membership: @user.workspace_memberships.first)
    assert_difference -> { TransactionRefund.count }, -1 do
      delete "/api/v1/transaction_refunds/#{refund.id}"
    end
    assert_response :no_content
    assert_equal 10_000, @debit.reload.effective_amount_cents
  end

  test "DELETE transaction_refunds/:id 404 cross-workspace" do
    other_ws = create(:workspace)
    acc = create(:account, workspace: other_ws)
    d = create(:transaction, workspace: other_ws, account: acc, direction: "debit")
    c = create(:transaction, workspace: other_ws, account: acc, direction: "credit")
    refund = create(:transaction_refund, refund_transaction: c, refunded_transaction: d,
                    confirmed_by_membership: create(:workspace_membership, workspace: other_ws))
    delete "/api/v1/transaction_refunds/#{refund.id}"
    assert_response :not_found
  end

  test "serializer exposes effective_amount_cents and refund block on the debit" do
    create(:transaction_refund, refund_transaction: @credit, refunded_transaction: @debit,
           confirmed_by_membership: @user.workspace_memberships.first)
    get "/api/v1/transactions", params: { status: "consolidated" }
    body = JSON.parse(response.body)["transactions"]
    debit_json = body.find { |t| t["id"] == @debit.id }
    assert_equal 0, debit_json["effective_amount_cents"]
    assert_equal 10_000, debit_json["refund"]["refunded_amount_cents"]
  end
end
