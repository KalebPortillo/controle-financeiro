require "test_helper"

# RF9 — recorrente detectada ou cadastrada manualmente.
class RecurrenceTest < ActiveSupport::TestCase
  test "factory builds a valid recurrence" do
    assert build(:recurrence).valid?
  end

  test "requires workspace, account and descriptor_pattern" do
    rec = Recurrence.new
    assert_not rec.valid?
    assert_includes rec.errors[:workspace], "must exist"
    assert_includes rec.errors[:account], "must exist"
    assert_includes rec.errors[:descriptor_pattern], "can't be blank"
  end

  test "cadence deve estar entre os valores permitidos" do
    rec = build(:recurrence, cadence: "daily")
    assert_not rec.valid?
    assert_includes rec.errors[:cadence], "is not included in the list"
  end

  test "status deve estar entre os valores permitidos" do
    rec = build(:recurrence, status: "frozen")
    assert_not rec.valid?
    assert_includes rec.errors[:status], "is not included in the list"
  end

  test "source deve estar entre os valores permitidos" do
    rec = build(:recurrence, source: "imported")
    assert_not rec.valid?
    assert_includes rec.errors[:source], "is not included in the list"
  end

  test "status default é active e amount_tolerance_pct default 5.00" do
    rec = Recurrence.new
    assert_equal "active", rec.status
    assert_equal 5.0, rec.amount_tolerance_pct.to_f
  end

  test "expected_amount_cents quando presente deve ser positivo" do
    rec = build(:recurrence, expected_amount_cents: 0)
    assert_not rec.valid?
    assert_includes rec.errors[:expected_amount_cents], "must be greater than 0"
  end

  test "expected_amount_cents pode ser nulo (valor variável)" do
    assert build(:recurrence, expected_amount_cents: nil).valid?
  end

  test "account deve pertencer ao mesmo workspace" do
    ws    = create(:workspace)
    other = create(:account, workspace: create(:workspace))
    rec   = build(:recurrence, workspace: ws, account: other)
    assert_not rec.valid?
    assert_includes rec.errors[:account], "deve pertencer ao workspace"
  end

  test "predicados de status" do
    assert build(:recurrence, status: "active").active?
    assert build(:recurrence, status: "paused").paused?
    assert build(:recurrence, status: "cancelled").cancelled?
  end
end
