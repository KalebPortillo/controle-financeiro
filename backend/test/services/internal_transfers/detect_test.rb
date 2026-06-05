require "test_helper"

class InternalTransfers::DetectTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
    @acc_a = create(:account, workspace: @workspace)
    @acc_b = create(:account, workspace: @workspace)
  end

  def debit(amount: 50_000, on: Date.current, account: @acc_a)
    create(:transaction, workspace: @workspace, account: account, direction: "debit",
           amount_cents: amount, status: "consolidated", occurred_at: on)
  end

  def credit(amount: 50_000, on: Date.current, account: @acc_b)
    create(:transaction, workspace: @workspace, account: account, direction: "credit",
           amount_cents: amount, status: "consolidated", occurred_at: on)
  end

  test "matches a debit to a same-value credit in another account within the window" do
    d = debit(on: Date.current)
    c = credit(on: Date.current + 1)

    created = InternalTransfers::Detect.call(workspace: @workspace)

    assert_equal 1, created.size
    transfer = InternalTransfer.find_by(debit_transaction: d, credit_transaction: c)
    assert transfer
    assert_nil transfer.confirmed_by_membership_id, "auto-detected → confirmed_by nil"
  end

  test "does not match a credit in the same account" do
    debit(account: @acc_a)
    credit(account: @acc_a)
    assert_empty InternalTransfers::Detect.call(workspace: @workspace)
  end

  test "does not match a credit with a different value" do
    debit(amount: 50_000)
    credit(amount: 49_999)
    assert_empty InternalTransfers::Detect.call(workspace: @workspace)
  end

  test "does not match outside the time window" do
    debit(on: Date.current)
    credit(on: Date.current + 10)
    assert_empty InternalTransfers::Detect.call(workspace: @workspace)
  end

  test "is idempotent — does not recreate existing transfers" do
    debit(on: Date.current)
    credit(on: Date.current)
    InternalTransfers::Detect.call(workspace: @workspace)
    assert_no_difference -> { InternalTransfer.count } do
      InternalTransfers::Detect.call(workspace: @workspace)
    end
  end

  test "does not reuse a transaction already in a transfer" do
    d1 = debit(on: Date.current)
    credit(on: Date.current) # pareia com d1
    InternalTransfers::Detect.call(workspace: @workspace)

    # novo débito de mesmo valor, mas o único crédito já está vinculado
    debit(on: Date.current, account: @acc_a)
    created = InternalTransfers::Detect.call(workspace: @workspace)
    assert_empty created
    assert_equal 1, InternalTransfer.where(debit_transaction: d1).count
  end
end
