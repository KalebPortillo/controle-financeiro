require "test_helper"

class WorkspacesApiTest < ActionDispatch::IntegrationTest
  # ---- auth gate -------------------------------------------------------

  test "GET /workspaces returns 401 when not signed in" do
    get "/api/v1/workspaces"
    assert_response :unauthorized
  end

  # ---- index -----------------------------------------------------------

  test "GET /workspaces returns only workspaces the user belongs to" do
    user  = create(:user)
    other = create(:user)
    own        = create(:workspace, name: "Mine",   created_by_user: user)
    invited_to = create(:workspace, name: "Shared", created_by_user: other)
    not_mine   = create(:workspace, name: "Theirs", created_by_user: other)
    create(:workspace_membership, user: user, workspace: own)
    create(:workspace_membership, user: user, workspace: invited_to)
    create(:workspace_membership, user: other, workspace: not_mine)

    sign_in_as(user)
    get "/api/v1/workspaces"
    assert_response :ok

    body = JSON.parse(response.body)
    ids = body["workspaces"].map { |w| w["id"] }
    assert_equal 2, ids.size
    assert_includes ids, own.id
    assert_includes ids, invited_to.id
    assert_not_includes ids, not_mine.id
  end

  # ---- create ----------------------------------------------------------

  test "POST /workspaces creates workspace owned by current user + editor membership" do
    user = create(:user)
    sign_in_as(user)

    assert_difference "Workspace.count", 1 do
      assert_difference "WorkspaceMembership.count", 1 do
        post "/api/v1/workspaces", params: { name: "Casal Portilho" }, as: :json
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "Casal Portilho", body.dig("workspace", "name")

    workspace = Workspace.find(body.dig("workspace", "id"))
    assert_equal user, workspace.created_by_user
    membership = workspace.memberships.first
    assert_equal user, membership.user
    assert_equal "editor", membership.role
  end

  test "POST /workspaces with blank name returns 422 in the canonical error shape" do
    sign_in_as(create(:user))
    post "/api/v1/workspaces", params: { name: "" }, as: :json
    assert_response :unprocessable_entity
    error = JSON.parse(response.body)["error"]
    assert_equal "validation_failed", error["code"]
    assert error["message"].present?
    # contratos-api.md v1.1: validação de model traz details[] por campo.
    assert_kind_of Array, error["details"]
    assert error["details"].any? { |d| d["field"] == "name" }
  end

  # ---- show ------------------------------------------------------------

  test "GET /workspaces/:id returns the workspace when user is a member" do
    user = create(:user)
    workspace = create(:workspace, name: "Mine", created_by_user: user)
    create(:workspace_membership, user: user, workspace: workspace)

    sign_in_as(user)
    get "/api/v1/workspaces/#{workspace.id}"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal workspace.id, body.dig("workspace", "id")
    assert_equal "Mine",       body.dig("workspace", "name")
  end

  test "GET /workspaces/:id returns 404 when user is not a member" do
    workspace = create(:workspace)
    sign_in_as(create(:user))
    get "/api/v1/workspaces/#{workspace.id}"
    assert_response :not_found
  end

  # ---- update ----------------------------------------------------------

  test "PATCH /workspaces/:id renames the workspace" do
    user = create(:user)
    workspace = create(:workspace, name: "Old", created_by_user: user)
    create(:workspace_membership, user: user, workspace: workspace)

    sign_in_as(user)
    patch "/api/v1/workspaces/#{workspace.id}", params: { name: "New" }, as: :json
    assert_response :ok
    assert_equal "New", workspace.reload.name
  end

  test "PATCH /workspaces/:id by non-member returns 404" do
    workspace = create(:workspace, name: "Old")
    sign_in_as(create(:user))
    patch "/api/v1/workspaces/#{workspace.id}", params: { name: "Hacked" }, as: :json
    assert_response :not_found
    assert_equal "Old", workspace.reload.name
  end
end
