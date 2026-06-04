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

  # ---- POST /onboarding/tags -----------------------------------------------

  test "POST /onboarding/tags creates tags and advances to categorizing" do
    @workspace.update!(onboarding_state: { "status" => "tagging" })

    assert_difference -> { @workspace.tags.count }, 2 do
      post "/api/v1/onboarding/tags",
           params: { accepted: [ { name: "Mercado" }, { name: "Padaria" } ] },
           as: :json
    end

    assert_response :ok
    state = @workspace.reload.onboarding_state
    assert_equal "categorizing", state["status"]
    assert_equal 2, state["accepted_tag_ids"].size
  end

  test "POST /onboarding/tags is idempotent on existing names (find_or_create)" do
    @workspace.update!(onboarding_state: { "status" => "tagging" })
    create(:tag, workspace: @workspace, name: "Mercado")

    assert_difference -> { @workspace.tags.count }, 0 do
      post "/api/v1/onboarding/tags",
           params: { accepted: [ { name: "Mercado" } ] }, as: :json
    end

    assert_response :ok
  end

  test "POST /onboarding/tags allows empty accepted array (skip via continue)" do
    @workspace.update!(onboarding_state: { "status" => "tagging" })

    assert_no_difference -> { @workspace.tags.count } do
      post "/api/v1/onboarding/tags", params: { accepted: [] }, as: :json
    end

    assert_response :ok
    assert_equal "categorizing", @workspace.reload.onboarding_state["status"]
  end

  # ---- POST /onboarding/categories -----------------------------------------

  test "POST /onboarding/categories creates categories with tags and completes" do
    @workspace.update!(onboarding_state: { "status" => "categorizing" })
    tag1 = create(:tag, workspace: @workspace, name: "Mercado")
    tag2 = create(:tag, workspace: @workspace, name: "Padaria")

    assert_difference -> { @workspace.categories.count }, 1 do
      post "/api/v1/onboarding/categories",
           params: { accepted: [ { name: "Alimentação", tag_ids: [ tag1.id, tag2.id ] } ] },
           as: :json
    end

    assert_response :ok
    state = @workspace.reload.onboarding_state
    assert_equal "completed", state["status"]
    assert state["completed_at"].present?

    category = @workspace.categories.find_by(name: "Alimentação")
    assert_equal [ tag1.id, tag2.id ].sort, category.tags.pluck(:id).sort
  end

  test "POST /onboarding/categories enqueues ReanalyzeJob on completion" do
    @workspace.update!(onboarding_state: { "status" => "categorizing" })

    assert_enqueued_with(job: AiSuggestion::ReanalyzeJob, args: [ @workspace.id ]) do
      post "/api/v1/onboarding/categories", params: { accepted: [] }, as: :json
    end
  end

  test "POST /onboarding/categories ignores tag_ids from other workspaces" do
    @workspace.update!(onboarding_state: { "status" => "categorizing" })
    foreign_tag = create(:tag, workspace: create(:workspace), name: "Foreign")

    post "/api/v1/onboarding/categories",
         params: { accepted: [ { name: "Casa", tag_ids: [ foreign_tag.id ] } ] },
         as: :json

    assert_response :ok
    category = @workspace.categories.find_by(name: "Casa")
    assert_equal 0, category.tags.count
  end

  # ---- GET /onboarding/suggestions/tags ------------------------------------

  test "GET /onboarding/suggestions/tags paginates by offset" do
    suggestions = (1..25).map { |i| { "name" => "Tag #{i}", "coverage" => i } }
    @workspace.update!(onboarding_state: {
      "status" => "tagging", "suggested_tags" => suggestions
    })

    get "/api/v1/onboarding/suggestions/tags", params: { offset: 0 }
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 10, body["tags"].size
    assert body["has_more"]

    get "/api/v1/onboarding/suggestions/tags", params: { offset: 20 }
    body = JSON.parse(response.body)
    assert_equal 5, body["tags"].size
    refute body["has_more"]
  end

  test "GET /onboarding/suggestions/categories paginates by offset" do
    suggestions = (1..15).map { |i| { "name" => "Cat #{i}", "tag_names" => [] } }
    @workspace.update!(onboarding_state: {
      "status" => "categorizing", "suggested_categories" => suggestions
    })

    get "/api/v1/onboarding/suggestions/categories", params: { offset: 0 }
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 10, body["categories"].size
    assert body["has_more"]
  end
end
