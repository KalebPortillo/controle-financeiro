require "test_helper"

class TransactionLinks::DetectIofTest < ActiveSupport::TestCase
  setup do
    @ws  = create(:workspace)
    @acc = create(:account, workspace: @ws, currency: "BRL")
  end

  def purchase(cents:, desc: "STORE US", occurred: Date.new(2026, 6, 20), currency: "USD")
    create(:transaction, workspace: @ws, account: @acc, direction: "debit",
           amount_cents: cents, occurred_at: occurred, original_description: desc,
           source_metadata: { "id" => SecureRandom.hex(4), "currencyCode" => currency })
  end

  def iof(cents:, desc: "IOF de compra internacional", occurred: Date.new(2026, 6, 22))
    create(:transaction, workspace: @ws, account: @acc, direction: "debit",
           amount_cents: cents, occurred_at: occurred, original_description: desc,
           source_metadata: { "id" => SecureRandom.hex(4),
                              "creditCardMetadata" => { "feeTypeAdditionalInfo" => "IOF_COMPRA_INTERNACIONAL" } })
  end

  test "links a generic IOF to the foreign purchase by 3.5% amount match" do
    buy = purchase(cents: 6527)          # R$65,27 × 3,5% = R$2,28
    tax = iof(cents: 228)

    assert_equal 1, TransactionLinks::DetectIof.call(workspace: @ws)
    link = tax.reload.link_as_related
    assert_equal buy, link.primary_transaction
    assert_equal "iof", link.relation_type
    assert_equal "automatic", link.origin
  end

  test "does not link when no purchase matches the rate" do
    purchase(cents: 10000) # 3,5% = 350, não bate com o IOF
    iof(cents: 228)

    assert_equal 0, TransactionLinks::DetectIof.call(workspace: @ws)
  end

  test "1:1 — two IOFs of equal value take distinct purchases" do
    b1 = purchase(cents: 6527, occurred: Date.new(2026, 6, 18))
    b2 = purchase(cents: 6527, occurred: Date.new(2026, 6, 20))
    i1 = iof(cents: 228, occurred: Date.new(2026, 6, 21))
    i2 = iof(cents: 228, occurred: Date.new(2026, 6, 23))

    assert_equal 2, TransactionLinks::DetectIof.call(workspace: @ws)
    primaries = [ i1, i2 ].map { |i| i.reload.link_as_related.primary_transaction_id }
    assert_equal [ b1.id, b2.id ].sort, primaries.sort
  end

  test "named IOF disambiguates by merchant among equal-value purchases" do
    _amazon = purchase(cents: 6527, desc: "AMAZON US", occurred: Date.new(2026, 6, 18))
    target  = purchase(cents: 6527, desc: "THREE GIRLS BAKERY", occurred: Date.new(2026, 6, 19))
    tax = iof(cents: 228, desc: 'IOF de "Three Girls Bakery"', occurred: Date.new(2026, 6, 21))

    TransactionLinks::DetectIof.call(workspace: @ws)
    assert_equal target, tax.reload.link_as_related.primary_transaction
  end

  test "idempotent: running twice creates no duplicate links" do
    purchase(cents: 6527)
    iof(cents: 228)

    assert_equal 1, TransactionLinks::DetectIof.call(workspace: @ws)
    assert_equal 0, TransactionLinks::DetectIof.call(workspace: @ws)
    assert_equal 1, TransactionLink.count
  end

  test "ignores domestic (non-foreign) purchases" do
    purchase(cents: 6527, currency: "BRL") # não é compra estrangeira
    iof(cents: 228)

    assert_equal 0, TransactionLinks::DetectIof.call(workspace: @ws)
  end
end
