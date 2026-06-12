require "test_helper"

# Ações em massa da inbox (RF2.3) — aceitar/rejeitar várias de uma vez num
# único request, em vez de N. update_all escopado no workspace e só em pending.
class TransactionsBulkTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
    @account    = create(:account, workspace: @workspace, owner_membership: @membership)
  end

  def pending
    create(:transaction, workspace: @workspace, account: @account, status: "pending")
  end

  test "bulk_consolidate aceita só as pendentes informadas, e ignora as já consolidadas" do
    a = pending
    b = pending
    already = create(:transaction, workspace: @workspace, account: @account, status: "consolidated")

    assert_no_enqueued_jobs do
      post "/api/v1/transactions/bulk_consolidate", params: { ids: [ a.id, b.id, already.id ] }, as: :json
    end

    assert_response :success
    assert_equal 2, JSON.parse(response.body)["count"]
    assert_equal "consolidated", a.reload.status
    assert_not_nil a.consolidated_at
    assert_equal "consolidated", b.reload.status
  end

  test "bulk_reject rejeita as pendentes informadas" do
    a = pending
    b = pending

    post "/api/v1/transactions/bulk_reject", params: { ids: [ a.id, b.id ] }, as: :json

    assert_response :success
    assert_equal 2, JSON.parse(response.body)["count"]
    assert_equal "rejected", a.reload.status
    assert_not_nil a.rejected_at
  end

  test "não toca em transações de outro workspace" do
    # A factory de :transaction cria conta+workspace próprios — workspace alheio.
    foreign = create(:transaction, status: "pending")

    post "/api/v1/transactions/bulk_consolidate", params: { ids: [ foreign.id ] }, as: :json

    assert_response :success
    assert_equal 0, JSON.parse(response.body)["count"]
    assert_equal "pending", foreign.reload.status
  end

  test "ids vazio é no-op" do
    post "/api/v1/transactions/bulk_consolidate", params: { ids: [] }, as: :json
    assert_response :success
    assert_equal 0, JSON.parse(response.body)["count"]
  end
end
