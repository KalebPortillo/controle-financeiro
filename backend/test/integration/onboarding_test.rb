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

  # ---- sessions/current includes onboarding ---------------------------------

  test "GET /sessions/current includes onboarding summary" do
    @workspace.update!(onboarding_state: { "status" => "tagging" })
    get "/api/v1/sessions/current"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "tagging", body.dig("onboarding", "status")
  end
end
