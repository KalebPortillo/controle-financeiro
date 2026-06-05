require "test_helper"

class OnboardingTest < ActionDispatch::IntegrationTest
  setup do
    @user      = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
    # Por padrão o user é o created_by_user via factory de workspace.
    @workspace.update!(created_by_user: @user)
  end

  # ---- GET /onboarding ------------------------------------------------------

  test "GET /onboarding returns the state of the active workspace" do
    get "/api/v1/onboarding"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "not_started", body["status"]
    assert_equal 0,             body["current_step"]
    assert_nil body["analysis_error"]
  end

  test "GET /onboarding exposes a recorded ai analysis error" do
    @workspace.update!(onboarding_state: { "status" => "analyzing" })
    @workspace.record_ai_error!(AiProviders::ApiError.new("HTTP 429 depleted", reason: :quota))

    get "/api/v1/onboarding"
    err = JSON.parse(response.body)["analysis_error"]
    assert_equal "quota", err["reason"]
    assert_match(/limite/i, err["message"])
  end

  test "POST /onboarding/advance to analyzing clears a previous ai error" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })
    @workspace.record_ai_error!(AiProviders::ApiError.new("x", reason: :quota))

    post "/api/v1/onboarding/advance", params: { to: "analyzing" }
    assert_nil @workspace.reload.ai_last_error
  end

  test "GET /onboarding requires authentication" do
    delete "/api/v1/sessions/current"
    get "/api/v1/onboarding"
    assert_response :unauthorized
  end

  test "GET /onboarding returns 403 when current_user is not workspace owner" do
    other_owner = create(:user)
    @workspace.update!(created_by_user: other_owner)

    get "/api/v1/onboarding"
    assert_response :forbidden
  end

  # ---- POST /onboarding/start ----------------------------------------------

  test "POST /onboarding/start moves status to connecting" do
    post "/api/v1/onboarding/start"
    assert_response :ok
    assert_equal "connecting", @workspace.reload.onboarding_state["status"]
  end

  test "POST /onboarding/start is idempotent" do
    post "/api/v1/onboarding/start"
    started_at = @workspace.reload.onboarding_state["started_at"]
    post "/api/v1/onboarding/start"
    assert_equal started_at, @workspace.reload.onboarding_state["started_at"]
  end

  test "POST /onboarding/start returns 422 when already completed" do
    @workspace.update!(onboarding_state: { "status" => "completed" })
    post "/api/v1/onboarding/start"
    assert_response :unprocessable_entity
  end

  # ---- POST /onboarding/skip ------------------------------------------------

  test "POST /onboarding/skip marks status as skipped" do
    post "/api/v1/onboarding/skip"
    assert_response :ok
    assert_equal "skipped", @workspace.reload.onboarding_state["status"]
  end

  # ---- POST /onboarding/advance --------------------------------------------

  test "POST /onboarding/advance moves to next step" do
    @workspace.update!(onboarding_state: { "status" => "tagging" })
    post "/api/v1/onboarding/advance"
    assert_response :ok
    assert_equal "categorizing", @workspace.reload.onboarding_state["status"]
  end

  test "POST /onboarding/advance accepts explicit to" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })
    post "/api/v1/onboarding/advance", params: { to: "completed" }, as: :json
    assert_response :ok
    assert_equal "completed", @workspace.reload.onboarding_state["status"]
  end

  test "POST /onboarding/advance returns 422 on invalid destination" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })
    post "/api/v1/onboarding/advance", params: { to: "garbage" }, as: :json
    assert_response :unprocessable_entity
  end

  # F2 — a análise IA é disparada pelo clique em "Continuar" (connecting→analyzing),
  # não mais automaticamente pelo fim do sync.
  test "POST /onboarding/advance to analyzing enqueues the AnalyzeJob" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })
    assert_enqueued_with(job: Onboarding::AnalyzeJob, args: [ @workspace.id ]) do
      post "/api/v1/onboarding/advance", params: { to: "analyzing" }, as: :json
    end
    assert_response :ok
    assert_equal "analyzing", @workspace.reload.onboarding_state["status"]
  end

  test "POST /onboarding/advance to other steps does not enqueue the AnalyzeJob" do
    @workspace.update!(onboarding_state: { "status" => "tagging" })
    assert_no_enqueued_jobs only: Onboarding::AnalyzeJob do
      post "/api/v1/onboarding/advance", params: { to: "categorizing" }, as: :json
    end
  end

  # B-cat-2 — entrar em categorizing dispara a 2ª análise (categorias das tags).
  test "POST /onboarding/advance to categorizing enqueues SuggestCategoriesJob" do
    @workspace.update!(onboarding_state: { "status" => "tagging" })
    assert_enqueued_with(job: Onboarding::SuggestCategoriesJob, args: [ @workspace.id ]) do
      post "/api/v1/onboarding/advance", params: { to: "categorizing" }, as: :json
    end
  end

  # ---- sessions/current includes onboarding ---------------------------------

  test "GET /sessions/current includes onboarding summary" do
    @workspace.update!(onboarding_state: { "status" => "tagging" })
    get "/api/v1/sessions/current"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "tagging", body.dig("onboarding", "status")
  end

  # R1 — concluir o onboarding (categorizing→completed) reanalisa a inbox com as
  # tags/categorias já criadas (RF22.6).
  test "POST /onboarding/advance to completed enqueues the ReanalyzeJob" do
    @workspace.update!(onboarding_state: { "status" => "categorizing" })
    assert_enqueued_with(job: AiSuggestion::ReanalyzeJob, args: [ @workspace.id ]) do
      post "/api/v1/onboarding/advance", params: { to: "completed" }, as: :json
    end
    assert_equal "completed", @workspace.reload.onboarding_state["status"]
  end
end
