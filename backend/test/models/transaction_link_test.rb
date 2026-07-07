require "test_helper"

class TransactionLinkTest < ActiveSupport::TestCase
  setup do
    @ws  = create(:workspace)
    @acc = create(:account, workspace: @ws)
  end

  def txn(**attrs)
    create(:transaction, **{ workspace: @ws, account: @acc }.merge(attrs))
  end

  test "factory builds a valid link" do
    assert build(:transaction_link).valid?
  end

  test "requires a valid relation_type" do
    link = build(:transaction_link, relation_type: "bogus")
    assert_not link.valid?
    assert_includes link.errors[:relation_type], "is not included in the list"
  end

  test "related transaction is unique per relation_type" do
    iof = txn
    buy = txn
    create(:transaction_link, workspace_obj: @ws, primary_transaction: buy, related_transaction: iof, relation_type: "iof")
    dup = build(:transaction_link, workspace_obj: @ws, primary_transaction: txn, related_transaction: iof, relation_type: "iof")
    assert_not dup.valid?
    assert_includes dup.errors[:related_transaction_id], "has already been taken"
  end

  test "cannot link a transaction to itself" do
    t = txn
    link = build(:transaction_link, workspace_obj: @ws, primary_transaction: t, related_transaction: t)
    assert_not link.valid?
  end

  test "primary and related must share the workspace" do
    other = create(:account) # outro workspace
    link = build(:transaction_link, workspace_obj: @ws,
                 primary_transaction: txn, related_transaction: create(:transaction, account: other, workspace: other.workspace))
    assert_not link.valid?
  end

  test "primary exposes related_links; related exposes link_as_related" do
    buy = txn
    iof = txn
    link = create(:transaction_link, workspace_obj: @ws, primary_transaction: buy, related_transaction: iof)
    assert_equal [ link ], buy.reload.related_links.to_a
    assert_equal link, iof.reload.link_as_related
  end
end
