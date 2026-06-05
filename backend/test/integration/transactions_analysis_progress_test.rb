require "test_helper"

# P4 — progresso real da análise IA: conta as pending do workspace e quantas já
# têm ai_suggestion (sinal de "analisada"). A barra anda em degraus de batch.
class TransactionsAnalysisProgressTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
    @account    = create(:account, workspace: @workspace, owner_membership: @membership)
  end

  def pending(analyzed:)
    create(:transaction, workspace: @workspace, account: @account, status: "pending",
           ai_suggestion: analyzed ? { "title" => "x", "suggested_at" => Time.current.iso8601 } : nil)
  end

  test "reports total, analyzed and done while analysis is in progress" do
    pending(analyzed: true)
    pending(analyzed: false)
    pending(analyzed: false)

    get "/api/v1/transactions/analysis_progress"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 3, body["total"]
    assert_equal 1, body["analyzed"]
    assert_equal false, body["done"]
  end

  test "done is true when every pending transaction is analyzed" do
    pending(analyzed: true)
    pending(analyzed: true)

    get "/api/v1/transactions/analysis_progress"
    body = JSON.parse(response.body)
    assert_equal 2, body["total"]
    assert_equal 2, body["analyzed"]
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
    pending(analyzed: false)
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
    pending(analyzed: false)
    @workspace.record_ai_error!(AiProviders::ApiError.new("HTTP 429 depleted", reason: :quota))

    get "/api/v1/transactions/analysis_progress"
    err = JSON.parse(response.body)["error"]
    assert_equal "quota", err["reason"]
    assert_match(/limite/i, err["message"])
  end

  test "error is null when there is none" do
    pending(analyzed: false)
    get "/api/v1/transactions/analysis_progress"
    assert_nil JSON.parse(response.body)["error"]
  end

  test "reanalyze clears a recorded ai error" do
    pending(analyzed: false)
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
