require "test_helper"

class Users::CreateWithPersonalWorkspaceTest < ActiveSupport::TestCase
  def google_auth(uid: "google-1", email: "kaleb@example.com", name: "Kaleb")
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name, image: nil }
    )
  end

  test "first sign-in creates user + personal workspace + editor membership" do
    user = nil
    assert_difference -> { User.count }, 1 do
      assert_difference -> { Workspace.count }, 1 do
        assert_difference -> { WorkspaceMembership.count }, 1 do
          user = Users::CreateWithPersonalWorkspace.call(google_auth)
        end
      end
    end

    workspace = user.workspaces.first
    assert_equal "Kaleb's workspace", workspace.name
    assert_equal user, workspace.created_by_user

    membership = user.workspace_memberships.first
    assert_equal "editor", membership.role
    assert_in_delta Time.current.to_f, membership.joined_at.to_f, 5
  end

  test "subsequent sign-in does not create extra workspace" do
    Users::CreateWithPersonalWorkspace.call(google_auth)

    assert_no_difference [ "User.count", "Workspace.count", "WorkspaceMembership.count" ] do
      Users::CreateWithPersonalWorkspace.call(google_auth)
    end
  end

  test "updates user profile fields from google on subsequent sign-in" do
    Users::CreateWithPersonalWorkspace.call(google_auth(name: "Old Name"))
    user = Users::CreateWithPersonalWorkspace.call(google_auth(name: "New Name"))
    assert_equal "New Name", user.name
  end

  test "matches existing user by google_uid (não cria duplicado por email)" do
    existing = create(:user, google_uid: "google-1", email: "stale@example.com")
    assert_no_difference "User.count" do
      user = Users::CreateWithPersonalWorkspace.call(google_auth(email: "kaleb@example.com"))
      assert_equal existing.id, user.id
      assert_equal "kaleb@example.com", user.reload.email
    end
  end
end
