require "test_helper"

class Budgets::HistoryTest < ActiveSupport::TestCase
  setup do
    @ws  = create(:workspace)
    @acc = create(:account, workspace: @ws)
    @tag = create(:tag, workspace: @ws)
    @budget = create(:budget, workspace: @ws, target_tag: @tag, monthly_limit_cents: 100_000)
    @today = Date.new(2026, 6, 15)
  end

  def spend(cents, on:)
    t = create(:transaction, workspace: @ws, account: @acc, direction: "debit",
               amount_cents: cents, status: "consolidated", occurred_at: on)
    t.tags = [ @tag ]
  end

  test "returns N months chronologically, current month last" do
    h = Budgets::History.call(budget: @budget, months: 6, today: @today)
    assert_equal 6, h.size
    assert_equal "2026-01", h.first.month
    assert_equal "2026-06", h.last.month
  end

  test "each month reflects only its own consolidated spend" do
    spend(20_000, on: Date.new(2026, 5, 10))
    spend(50_000, on: Date.new(2026, 6, 3))

    h = Budgets::History.call(budget: @budget, months: 6, today: @today)
    may  = h.find { |e| e.month == "2026-05" }
    june = h.find { |e| e.month == "2026-06" }
    assert_equal 20_000, may.spent_cents
    assert_equal 50_000, june.spent_cents
    assert_equal 50, june.pct
    assert_equal "ok", june.status
  end
end
