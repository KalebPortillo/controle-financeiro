require "test_helper"

class TransactionLinks::OriginCandidatesTest < ActiveSupport::TestCase
  setup do
    @ws   = create(:workspace)
    @acc  = create(:account, workspace: @ws)
    @acc2 = create(:account, workspace: @ws)
  end

  def tx(account: @acc, **attrs)
    create(:transaction, workspace: @ws, account: account, **attrs)
  end

  test "lists same-account transactions, excluding the satellite itself" do
    satellite = tx(direction: "debit", amount_cents: 120, original_description: "TARIFA")
    origin    = tx(direction: "debit", amount_cents: 5000, original_description: "COMPRA")

    ids = TransactionLinks::OriginCandidates.call(related: satellite).map(&:id)
    assert_includes ids, origin.id
    assert_not_includes ids, satellite.id
  end

  test "excludes transactions from other accounts" do
    satellite = tx(direction: "debit", amount_cents: 120)
    other     = tx(account: @acc2, direction: "debit", amount_cents: 5000)

    ids = TransactionLinks::OriginCandidates.call(related: satellite).map(&:id)
    assert_not_includes ids, other.id
  end

  test "filters by search query" do
    satellite = tx(direction: "debit", amount_cents: 120)
    figma     = tx(direction: "debit", amount_cents: 5000, original_description: "FIGMA")
    _spotify  = tx(direction: "debit", amount_cents: 3000, original_description: "SPOTIFY")

    ids = TransactionLinks::OriginCandidates.call(related: satellite, q: "figma").map(&:id)
    assert_equal [ figma.id ], ids
  end

  test "excludes the origin already linked to this satellite" do
    membership = @ws.memberships.first || create(:workspace_membership, workspace: @ws)
    satellite  = tx(direction: "debit", amount_cents: 120)
    origin     = tx(direction: "debit", amount_cents: 5000)
    TransactionLinks::Create.call(workspace: @ws, primary: origin, related: satellite,
                                  relation_type: "fee", membership: membership)

    ids = TransactionLinks::OriginCandidates.call(related: satellite).map(&:id)
    assert_not_includes ids, origin.id
  end
end
