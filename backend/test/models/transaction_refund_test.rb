require "test_helper"

# RF10 — vínculo de estorno (credit) a um gasto original (debit). O valor
# efetivo do gasto é calculado por query (amount - SUM(refunds)), não mutado.
class TransactionRefundTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
    @membership = create(:workspace_membership, workspace: @workspace)
    @debit  = create(:transaction, workspace: @workspace, account: @account,
                     direction: "debit", amount_cents: 10_000, status: "consolidated")
    @credit = create(:transaction, workspace: @workspace, account: @account,
                     direction: "credit", amount_cents: 4_000, status: "consolidated")
  end

  def build_refund(refund: @credit, refunded: @debit)
    build(:transaction_refund, refund_transaction: refund, refunded_transaction: refunded,
          confirmed_by_membership: @membership)
  end

  test "valid factory" do
    assert build_refund.valid?
  end

  test "refund transaction must be a credit" do
    r = build_refund(refund: @debit)
    assert_not r.valid?
    assert_includes r.errors[:refund_transaction], "deve ser um crédito"
  end

  test "refunded transaction must be a debit" do
    r = build_refund(refunded: @credit)
    assert_not r.valid?
    assert_includes r.errors[:refunded_transaction], "deve ser um débito"
  end

  test "both transactions must be in the same workspace" do
    foreign_debit = create(:transaction, workspace: create(:workspace),
                           account: create(:account), direction: "debit")
    r = build_refund(refunded: foreign_debit)
    assert_not r.valid?
    assert_includes r.errors[:base], "estorno e gasto devem ser do mesmo workspace"
  end

  test "a credit can refund only one debit (unique refund_transaction)" do
    build_refund.save!
    other_debit = create(:transaction, workspace: @workspace, account: @account, direction: "debit")
    dup = build_refund(refunded: other_debit)
    assert_not dup.valid?
  end

  # Transaction#effective_amount_cents / refunded? / refunded_amount_cents
  test "effective amount of a refunded debit subtracts the refund" do
    build_refund.save!
    assert_equal 4_000, @debit.reload.refunded_amount_cents
    assert_equal 6_000, @debit.effective_amount_cents
    assert @debit.refunded?
  end

  test "effective amount never goes below zero (over-refund)" do
    create(:transaction, workspace: @workspace, account: @account, direction: "credit",
           amount_cents: 9_000, status: "consolidated").then do |big|
      create(:transaction_refund, refund_transaction: big, refunded_transaction: @debit,
             confirmed_by_membership: @membership)
    end
    build_refund.save! # +4000, total 13000 > 10000
    assert_equal 0, @debit.reload.effective_amount_cents
  end

  test "a debit with no refunds has effective == amount and is not refunded" do
    assert_equal @debit.amount_cents, @debit.effective_amount_cents
    assert_not @debit.refunded?
  end
end
