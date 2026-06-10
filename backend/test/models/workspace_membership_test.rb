require "test_helper"

class WorkspaceMembershipTest < ActiveSupport::TestCase
  test "factory builds a valid membership" do
    assert build(:workspace_membership).valid?
  end

  test "requires user, workspace, role and joined_at" do
    membership = WorkspaceMembership.new
    assert_not membership.valid?
    assert_includes membership.errors[:user],      "must exist"
    assert_includes membership.errors[:workspace], "must exist"
    assert_includes membership.errors[:joined_at], "can't be blank"
  end

  test "defaults role to editor" do
    membership = WorkspaceMembership.new
    assert_equal "editor", membership.role
  end

  test "role must be editor or viewer" do
    membership = build(:workspace_membership, role: "admin")
    assert_not membership.valid?
    assert_includes membership.errors[:role], "is not included in the list"
  end

  test "destroying membership nullifies owned bank_connections and accounts" do
    membership = create(:workspace_membership)
    connection = create(:bank_connection, workspace: membership.workspace, owner_membership: membership)
    account    = create(:account, workspace: membership.workspace, owner_membership: membership)

    membership.destroy!

    assert_nil connection.reload.owner_membership_id
    assert_nil account.reload.owner_membership_id
  end

  test "(user_id, workspace_id) is unique" do
    user      = create(:user)
    workspace = create(:workspace)
    create(:workspace_membership, user: user, workspace: workspace)

    dup = build(:workspace_membership, user: user, workspace: workspace)
    assert_not dup.valid?
    assert_includes dup.errors[:user_id], "has already been taken"
  end
end
