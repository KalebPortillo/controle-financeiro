require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "factory builds a valid user" do
    assert build(:user).valid?
  end

  test "requires email, google_uid and name" do
    user = User.new
    assert_not user.valid?
    assert_includes user.errors[:email],      "can't be blank"
    assert_includes user.errors[:google_uid], "can't be blank"
    assert_includes user.errors[:name],       "can't be blank"
  end

  test "email is unique case-insensitively" do
    create(:user, email: "ana@example.com")
    dup = build(:user, email: "ANA@example.com")
    assert_not dup.valid?
    assert_includes dup.errors[:email], "has already been taken"
  end

  test "google_uid is unique" do
    create(:user, google_uid: "google-1")
    dup = build(:user, google_uid: "google-1")
    assert_not dup.valid?
    assert_includes dup.errors[:google_uid], "has already been taken"
  end

  test "email format is validated" do
    user = build(:user, email: "not-an-email")
    assert_not user.valid?
    assert_includes user.errors[:email], "is invalid"
  end

  test "owns memberships and workspaces through them" do
    user = create(:user)
    workspace_a = create(:workspace)
    workspace_b = create(:workspace)
    create(:workspace_membership, user: user, workspace: workspace_a)
    create(:workspace_membership, user: user, workspace: workspace_b)

    assert_equal 2, user.workspace_memberships.count
    assert_includes user.workspaces, workspace_a
    assert_includes user.workspaces, workspace_b
  end
end
