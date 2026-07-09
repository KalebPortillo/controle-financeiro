require "test_helper"

# RF9.7 — item removido manualmente do grupo de uma recorrência.
class RecurrenceExclusionTest < ActiveSupport::TestCase
  test "factory builds a valid exclusion" do
    assert build(:recurrence_exclusion).valid?
  end

  test "requires recurrence, transaction and workspace" do
    ex = RecurrenceExclusion.new
    assert_not ex.valid?
    assert_includes ex.errors[:recurrence], "must exist"
    assert_includes ex.errors[:excluded_transaction], "must exist"
    assert_includes ex.errors[:workspace], "must exist"
  end

  test "a mesma transação não pode ser excluída duas vezes da mesma recorrência" do
    ex = create(:recurrence_exclusion)
    dup = build(:recurrence_exclusion, recurrence: ex.recurrence,
                excluded_transaction: ex.excluded_transaction, workspace: ex.workspace)
    assert_not dup.valid?
    assert_includes dup.errors[:transaction_id], "has already been taken"
  end
end
