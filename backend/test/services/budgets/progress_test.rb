require "test_helper"

class Budgets::ProgressTest < ActiveSupport::TestCase
  setup do
    @ws   = create(:workspace)
    @acc  = create(:account, workspace: @ws)
    @from = Date.new(2026, 6, 1)
    @to   = Date.new(2026, 6, 30)
  end

  def gasto(cents:, tags:, status: "consolidated", occurred: Date.new(2026, 6, 10))
    t = create(:transaction, workspace: @ws, account: @acc, direction: "debit",
               amount_cents: cents, occurred_at: occurred, status: status)
    t.tags = tags
    t
  end

  test "tag budget: sums consolidated debits with the tag" do
    tag = create(:tag, workspace: @ws)
    gasto(cents: 30_000, tags: [ tag ])
    gasto(cents: 12_300, tags: [ tag ])
    gasto(cents: 99_999, tags: [ create(:tag, workspace: @ws) ]) # outra tag, ignora
    budget = create(:budget, workspace: @ws, target_tag: tag, monthly_limit_cents: 80_000)

    r = Budgets::Progress.call(budget: budget, from: @from, to: @to, today: Date.new(2026, 6, 30))
    assert_equal 42_300, r.spent_cents
    assert_equal 53, r.pct
    assert_equal "ok", r.status
    assert_equal 37_700, r.remaining_cents
  end

  test "ignores pending (inbox) transactions — RF8.6" do
    tag = create(:tag, workspace: @ws)
    gasto(cents: 30_000, tags: [ tag ], status: "pending")
    budget = create(:budget, workspace: @ws, target_tag: tag, monthly_limit_cents: 80_000)
    assert_equal 0, Budgets::Progress.call(budget: budget, from: @from, to: @to).spent_cents
  end

  test "a transaction with two tracked tags counts once (no double-count)" do
    t1 = create(:tag, workspace: @ws)
    t2 = create(:tag, workspace: @ws)
    gasto(cents: 20_000, tags: [ t1, t2 ]) # ambas rastreadas pelo composto
    budget = create(:budget, :composite, workspace: @ws, composite_tags: [ t1, t2 ], monthly_limit_cents: 100_000)
    assert_equal 20_000, Budgets::Progress.call(budget: budget, from: @from, to: @to).spent_cents
  end

  test "category budget sums across all category tags" do
    t1 = create(:tag, workspace: @ws)
    t2 = create(:tag, workspace: @ws)
    cat = create(:category, workspace: @ws, tags: [ t1, t2 ])
    gasto(cents: 15_000, tags: [ t1 ])
    gasto(cents: 25_000, tags: [ t2 ])
    budget = create(:budget, :category, workspace: @ws, target_category: cat, monthly_limit_cents: 100_000)
    assert_equal 40_000, Budgets::Progress.call(budget: budget, from: @from, to: @to).spent_cents
  end

  test "status warning at threshold, exceeded at/over 100" do
    tag = create(:tag, workspace: @ws)
    gasto(cents: 85_000, tags: [ tag ])
    budget = create(:budget, workspace: @ws, target_tag: tag, monthly_limit_cents: 100_000, alert_threshold_pct: 80)
    r = Budgets::Progress.call(budget: budget, from: @from, to: @to)
    assert_equal "warning", r.status

    gasto(cents: 20_000, tags: [ tag ]) # total 105_000 > teto
    r2 = Budgets::Progress.call(budget: budget, from: @from, to: @to)
    assert_equal "exceeded", r2.status
    assert r2.remaining_cents.negative?
  end

  test "projection extrapolates by run-rate mid-month" do
    tag = create(:tag, workspace: @ws)
    gasto(cents: 30_000, tags: [ tag ], occurred: Date.new(2026, 6, 5))
    budget = create(:budget, workspace: @ws, target_tag: tag, monthly_limit_cents: 100_000)
    # dia 15 de 30: 15 decorridos → projeção = 30_000 * 30/15 = 60_000
    r = Budgets::Progress.call(budget: budget, from: @from, to: @to, today: Date.new(2026, 6, 15))
    assert_equal 60_000, r.projection_cents
  end

  test "projection equals spent once the period is over" do
    tag = create(:tag, workspace: @ws)
    gasto(cents: 30_000, tags: [ tag ])
    budget = create(:budget, workspace: @ws, target_tag: tag, monthly_limit_cents: 100_000)
    r = Budgets::Progress.call(budget: budget, from: @from, to: @to, today: Date.new(2026, 7, 1))
    assert_equal 30_000, r.projection_cents
  end
end
