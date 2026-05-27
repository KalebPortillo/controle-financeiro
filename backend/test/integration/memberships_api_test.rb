require "test_helper"

class MembershipsApiTest < ActionDispatch::IntegrationTest
  # ---- index -----------------------------------------------------------

  test "GET /workspaces/:id/memberships lists members when caller is one" do
    owner   = create(:user, name: "Owner")
    partner = create(:user, name: "Partner")
    workspace = create(:workspace, created_by_user: owner)
    create(:workspace_membership, user: owner,   workspace: workspace)
    create(:workspace_membership, user: partner, workspace: workspace)

    sign_in_as(owner)
    get "/api/v1/workspaces/#{workspace.id}/memberships"
    assert_response :ok

    body = JSON.parse(response.body)
    user_ids = body["memberships"].map { |m| m.dig("user", "id") }
    assert_includes user_ids, owner.id
    assert_includes user_ids, partner.id
  end

  test "GET /workspaces/:id/memberships returns 404 when caller is not a member" do
    workspace = create(:workspace)
    sign_in_as(create(:user))
    get "/api/v1/workspaces/#{workspace.id}/memberships"
    assert_response :not_found
  end

  # ---- create (RF16.3 convite por email) -------------------------------

  test "POST /workspaces/:id/memberships adds a registered user by email" do
    owner    = create(:user)
    invitee  = create(:user, email: "wife@example.com")
    workspace = create(:workspace, created_by_user: owner)
    create(:workspace_membership, user: owner, workspace: workspace)

    sign_in_as(owner)
    assert_difference "WorkspaceMembership.count", 1 do
      post "/api/v1/workspaces/#{workspace.id}/memberships",
           params: { email: "wife@example.com" }, as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal invitee.id, body.dig("membership", "user", "id")
    assert_equal "editor",   body.dig("membership", "role")
  end

  test "POST /workspaces/:id/memberships matches email case-insensitively" do
    owner   = create(:user)
    invitee = create(:user, email: "Wife@example.com")
    workspace = create(:workspace, created_by_user: owner)
    create(:workspace_membership, user: owner, workspace: workspace)

    sign_in_as(owner)
    post "/api/v1/workspaces/#{workspace.id}/memberships",
         params: { email: "wife@EXAMPLE.com" }, as: :json
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal invitee.id, body.dig("membership", "user", "id")
  end

  test "POST /workspaces/:id/memberships returns 404 when email not registered" do
    owner = create(:user)
    workspace = create(:workspace, created_by_user: owner)
    create(:workspace_membership, user: owner, workspace: workspace)

    sign_in_as(owner)
    post "/api/v1/workspaces/#{workspace.id}/memberships",
         params: { email: "nobody@example.com" }, as: :json
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "user_not_found", body.dig("error", "code")
  end

  test "POST /workspaces/:id/memberships is idempotent (already a member)" do
    owner    = create(:user)
    invitee  = create(:user, email: "wife@example.com")
    workspace = create(:workspace, created_by_user: owner)
    create(:workspace_membership, user: owner,   workspace: workspace)
    create(:workspace_membership, user: invitee, workspace: workspace)

    sign_in_as(owner)
    assert_no_difference "WorkspaceMembership.count" do
      post "/api/v1/workspaces/#{workspace.id}/memberships",
           params: { email: "wife@example.com" }, as: :json
    end
    assert_response :ok
  end

  test "POST /workspaces/:id/memberships returns 404 when caller is not a member" do
    workspace = create(:workspace)
    create(:user, email: "wife@example.com")

    sign_in_as(create(:user))
    post "/api/v1/workspaces/#{workspace.id}/memberships",
         params: { email: "wife@example.com" }, as: :json
    assert_response :not_found
  end

  # ---- destroy ---------------------------------------------------------

  test "DELETE /memberships/:id removes a membership" do
    owner   = create(:user)
    partner = create(:user)
    workspace = create(:workspace, created_by_user: owner)
    create(:workspace_membership, user: owner, workspace: workspace)
    partner_membership = create(:workspace_membership, user: partner, workspace: workspace)

    sign_in_as(owner)
    assert_difference "WorkspaceMembership.count", -1 do
      delete "/api/v1/workspaces/#{workspace.id}/memberships/#{partner_membership.id}"
    end
    assert_response :no_content
  end

  test "DELETE /memberships/:id by non-member returns 404" do
    owner   = create(:user)
    partner = create(:user)
    workspace = create(:workspace, created_by_user: owner)
    create(:workspace_membership, user: owner, workspace: workspace)
    partner_membership = create(:workspace_membership, user: partner, workspace: workspace)

    sign_in_as(create(:user))
    delete "/api/v1/workspaces/#{workspace.id}/memberships/#{partner_membership.id}"
    assert_response :not_found
    assert WorkspaceMembership.exists?(partner_membership.id)
  end
end
