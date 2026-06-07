require "test_helper"

# Progresso real da análise IA, por estado explícito (ai_status): queued/analyzed/
# failed. `done` quando ninguém está aguardando — failed NÃO trava o progresso.
class TransactionsAnalysisProgressTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
    @account    = create(:account, workspace: @workspace, owner_membership: @membership)
  end

  def pending(ai_status:)
    create(:transaction, workspace: @workspace, account: @account, status: "pending", ai_status: ai_status)
  end

  test "reports counts and done=false while some are still queued" do
    pending(ai_status: "analyzed")
    pending(ai_status: "queued")
    pending(ai_status: "queued")

    get "/api/v1/transactions/analysis_progress"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 3, body["total"]
    assert_equal 1, body["analyzed"]
    assert_equal 2, body["awaiting"]
    assert_equal false, body["done"]
  end

  # Regressão do deadlock: com 'failed' (não analisada, mas NÃO aguardando) e
  # nenhuma 'queued', o progresso CHEGA a done — a inbox não trava em "Analisando…".
  test "done is true with failed transactions as long as none are queued" do
    pending(ai_status: "analyzed")
    pending(ai_status: "failed")
    pending(ai_status: "failed")

    get "/api/v1/transactions/analysis_progress"
    body = JSON.parse(response.body)
    assert_equal 3, body["total"]
    assert_equal 1, body["analyzed"]
    assert_equal 2, body["failed"]
    assert_equal 0, body["awaiting"]
    assert_equal true, body["done"]
  end

  test "done is true and counts are zero when there is nothing pending" do
    get "/api/v1/transactions/analysis_progress"
    body = JSON.parse(response.body)
    assert_equal 0, body["total"]
    assert_equal 0, body["analyzed"]
    assert_equal true, body["done"]
  end

  test "ignores non-pending and other-workspace transactions" do
    pending(ai_status: "queued")
    create(:transaction, workspace: @workspace, account: @account, status: "consolidated",
           consolidated_at: Time.current)
    other = create(:workspace)
    create(:transaction, workspace: other, account: create(:account, workspace: other),
           status: "pending")

    get "/api/v1/transactions/analysis_progress"
    body = JSON.parse(response.body)
    assert_equal 1, body["total"]
  end

  test "exposes the ai error when one is recorded" do
    pending(ai_status: "failed")
    @workspace.record_ai_error!(AiProviders::ApiError.new("HTTP 429 depleted", reason: :quota))

    get "/api/v1/transactions/analysis_progress"
    err = JSON.parse(response.body)["error"]
    assert_equal "quota", err["reason"]
    assert_match(/limite/i, err["message"])
  end

  test "error is null when there is none" do
    pending(ai_status: "failed")
    get "/api/v1/transactions/analysis_progress"
    assert_nil JSON.parse(response.body)["error"]
  end

  test "reanalyze clears a recorded ai error" do
    pending(ai_status: "failed")
    @workspace.record_ai_error!(AiProviders::ApiError.new("x", reason: :quota))

    post "/api/v1/transactions/reanalyze"
    assert_response :accepted
    assert_nil @workspace.reload.ai_last_error
  end

  test "requires authentication" do
    delete "/api/v1/sessions/current"
    get "/api/v1/transactions/analysis_progress"
    assert_response :unauthorized
  end
end
