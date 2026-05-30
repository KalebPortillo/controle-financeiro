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

  # RF9.6 — last_seen_at e missed?.
  test "last_seen_at é a data da última transação consolidada que casa o padrão" do
    ws  = create(:workspace)
    ac  = create(:account, workspace: ws)
    rec = create(:recurrence, workspace: ws, account: ac, descriptor_pattern: "NETFLIX COM")
    create(:transaction, workspace: ws, account: ac, direction: "debit",
           original_description: "NETFLIX.COM 1", occurred_at: Date.new(2026, 1, 10),
           status: "consolidated", consolidated_at: Time.current)
    create(:transaction, workspace: ws, account: ac, direction: "debit",
           original_description: "NETFLIX.COM 2", occurred_at: Date.new(2026, 2, 10),
           status: "consolidated", consolidated_at: Time.current)
    # ruído: outro estabelecimento não conta
    create(:transaction, workspace: ws, account: ac, direction: "debit",
           original_description: "SPOTIFY", occurred_at: Date.new(2026, 3, 1),
           status: "consolidated", consolidated_at: Time.current)

    assert_equal Date.new(2026, 2, 10), rec.last_seen_at
  end

  test "missed? true quando vencida e nada chegou (com grace)" do
    rec = build(:recurrence, status: "active", next_expected_at: Date.new(2026, 1, 1))
    def rec.last_seen_at = nil
    assert rec.missed?(today: Date.new(2026, 1, 20))
    assert_not rec.missed?(today: Date.new(2026, 1, 2)) # dentro do grace
  end

  test "missed? false quando pausada/cancelada ou sem next_expected_at" do
    assert_not build(:recurrence, status: "paused", next_expected_at: Date.new(2026, 1, 1)).missed?(today: Date.new(2026, 2, 1))
    assert_not build(:recurrence, status: "active", next_expected_at: nil).missed?(today: Date.new(2026, 2, 1))
  end

  test "missed? false quando a transação chegou depois do esperado" do
    rec = build(:recurrence, status: "active", next_expected_at: Date.new(2026, 1, 1))
    def rec.last_seen_at = Date.new(2026, 1, 3)
    assert_not rec.missed?(today: Date.new(2026, 1, 20))
  end
end
