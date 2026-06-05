require "test_helper"

# RF11 — transferência interna: par débito (saída) + crédito (entrada) entre
# contas do mesmo workspace, que não conta como gasto/receita.
class InternalTransferTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
    @acc_a = create(:account, workspace: @workspace)
    @acc_b = create(:account, workspace: @workspace)
    @debit  = create(:transaction, workspace: @workspace, account: @acc_a,
                     direction: "debit", amount_cents: 50_000, status: "consolidated")
    @credit = create(:transaction, workspace: @workspace, account: @acc_b,
                     direction: "credit", amount_cents: 50_000, status: "consolidated")
  end

  def build_transfer(debit: @debit, credit: @credit)
    build(:internal_transfer, workspace: @workspace,
          debit_transaction: debit, credit_transaction: credit)
  end

  test "valid factory" do
    assert build_transfer.valid?
  end

  test "debit must be a debit and credit must be a credit" do
    t = build_transfer(debit: @credit, credit: @debit)
    assert_not t.valid?
  end

  test "the two transactions must be in different accounts" do
    same_acc_credit = create(:transaction, workspace: @workspace, account: @acc_a,
                             direction: "credit", amount_cents: 50_000)
    t = build_transfer(credit: same_acc_credit)
    assert_not t.valid?
    assert_includes t.errors[:base], "as contas devem ser diferentes"
  end

  test "both transactions must belong to the workspace" do
    foreign = create(:transaction, workspace: create(:workspace),
                     account: create(:account), direction: "credit", amount_cents: 50_000)
    t = build_transfer(credit: foreign)
    assert_not t.valid?
  end

  test "a transaction participates in at most one transfer (unique fks)" do
    build_transfer.save!
    other_credit = create(:transaction, workspace: @workspace, account: @acc_b, direction: "credit")
    dup = build_transfer(credit: other_credit)
    assert_not dup.valid?
  end

  test "Transaction#internal_transfer? reflects participation" do
    assert_not @debit.internal_transfer?
    build_transfer.save!
    assert @debit.reload.internal_transfer?
    assert @credit.reload.internal_transfer?
  end
end
