require "test_helper"

class WorkspaceSelectionTest < ActionDispatch::IntegrationTest
  test "GET /sessions/current returns the active workspace id" do
    user      = create(:user)
    workspace = create(:workspace, created_by_user: user)
    create(:workspace_membership, user: user, workspace: workspace)

    sign_in_as(user)

    get "/api/v1/sessions/current"
    body = JSON.parse(response.body)
    # Por default, a sessão recém-logada usa o primeiro workspace do user.
    assert_equal workspace.id, body["active_workspace_id"]
  end

  test "POST /sessions/current/select_workspace switches the active workspace" do
    user = create(:user)
    a = create(:workspace, name: "A", created_by_user: user)
    b = create(:workspace, name: "B", created_by_user: user)
    create(:workspace_membership, user: user, workspace: a)
    create(:workspace_membership, user: user, workspace: b)

    sign_in_as(user)

    post "/api/v1/sessions/current/select_workspace",
         params: { workspace_id: b.id }, as: :json
    assert_response :ok

    get "/api/v1/sessions/current"
    body = JSON.parse(response.body)
    assert_equal b.id, body["active_workspace_id"]
  end

  test "POST /sessions/current/select_workspace rejects a non-member workspace" do
    user      = create(:user)
    own       = create(:workspace, created_by_user: user)
    not_mine  = create(:workspace)
    create(:workspace_membership, user: user, workspace: own)

    sign_in_as(user)

    post "/api/v1/sessions/current/select_workspace",
         params: { workspace_id: not_mine.id }, as: :json
    assert_response :not_found

    get "/api/v1/sessions/current"
    body = JSON.parse(response.body)
    # active_workspace_id permanece no original
    assert_equal own.id, body["active_workspace_id"]
  end

  test "POST /sessions/current/select_workspace requires authentication" do
    workspace = create(:workspace)
    post "/api/v1/sessions/current/select_workspace",
         params: { workspace_id: workspace.id }, as: :json
    assert_response :unauthorized
  end
end
