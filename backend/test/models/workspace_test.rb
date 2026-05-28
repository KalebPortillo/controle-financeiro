require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  test "factory builds a valid workspace" do
    assert build(:workspace).valid?
  end

  test "requires name and created_by_user" do
    workspace = Workspace.new
    assert_not workspace.valid?
    assert_includes workspace.errors[:name], "can't be blank"
    assert_includes workspace.errors[:created_by_user], "must exist"
  end

  test "belongs to created_by_user" do
    user = create(:user)
    workspace = create(:workspace, created_by_user: user)
    assert_equal user, workspace.created_by_user
  end

  test "has many memberships and members through them" do
    workspace = create(:workspace)
    user_a    = create(:user)
    user_b    = create(:user)
    create(:workspace_membership, workspace: workspace, user: user_a)
    create(:workspace_membership, workspace: workspace, user: user_b)

    assert_equal 2, workspace.memberships.count
    assert_includes workspace.members, user_a
    assert_includes workspace.members, user_b
  end

  test "destroy cascateia connections/accounts/transactions antes das memberships (sem FK violation)" do
    workspace  = create(:workspace)
    membership = create(:workspace_membership, workspace: workspace)
    connection = create(:bank_connection, workspace: workspace, owner_membership: membership)
    account    = create(:account, workspace: workspace, owner_membership: membership,
                                  bank_connection: connection)
    create(:transaction, workspace: workspace, account: account)

    assert_nothing_raised { workspace.destroy! }
    assert_not Workspace.exists?(workspace.id)
    assert_not WorkspaceMembership.exists?(membership.id)
    assert_not BankConnection.exists?(connection.id)
    assert_not Account.exists?(account.id)
  end
end
