require "test_helper"

class TransactionLinks::CreateTest < ActiveSupport::TestCase
  setup do
    @ws         = create(:workspace)
    @membership = @ws.memberships.first || create(:workspace_membership, workspace: @ws)
    @acc        = create(:account, workspace: @ws)
  end

  def tx(**attrs)
    create(:transaction, workspace: @ws, account: @acc, **attrs)
  end

  test "creates a manual, confirmed link between origin and satellite" do
    origin    = tx(direction: "debit", amount_cents: 5000)
    satellite = tx(direction: "debit", amount_cents: 120)

    link = TransactionLinks::Create.call(
      workspace: @ws, primary: origin, related: satellite,
      relation_type: "fee", membership: @membership
    )

    assert_equal origin, link.primary_transaction
    assert_equal satellite, link.related_transaction
    assert_equal "fee", link.relation_type
    assert_equal "manual", link.origin
    assert_equal @membership, link.confirmed_by_membership
  end

  test "rejects linking a transaction to itself" do
    t = tx(direction: "debit", amount_cents: 5000)
    assert_raises(ActiveRecord::RecordInvalid) do
      TransactionLinks::Create.call(
        workspace: @ws, primary: t, related: t,
        relation_type: "fee", membership: @membership
      )
    end
  end

  test "rejects a second origin for the same satellite and type (uniqueness)" do
    origin1   = tx(direction: "debit", amount_cents: 5000)
    origin2   = tx(direction: "debit", amount_cents: 7000)
    satellite = tx(direction: "debit", amount_cents: 120)

    TransactionLinks::Create.call(workspace: @ws, primary: origin1, related: satellite,
                                  relation_type: "fee", membership: @membership)
    assert_raises(ActiveRecord::RecordInvalid) do
      TransactionLinks::Create.call(workspace: @ws, primary: origin2, related: satellite,
                                    relation_type: "fee", membership: @membership)
    end
  end
end
