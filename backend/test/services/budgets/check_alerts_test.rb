require "test_helper"

class Budgets::CheckAlertsTest < ActiveSupport::TestCase
  setup do
    @ws  = create(:workspace)
    @acc = create(:account, workspace: @ws)
    @tag = create(:tag, workspace: @ws)
  end

  def spend(cents)
    t = create(:transaction, workspace: @ws, account: @acc, direction: "debit",
               amount_cents: cents, status: "consolidated", occurred_at: Date.current)
    t.tags = [ @tag ]
    t
  end

  test "fires budget_warning when crossing the threshold" do
    create(:budget, workspace: @ws, target_tag: @tag, monthly_limit_cents: 100_000, alert_threshold_pct: 80)
    spend(85_000)

    assert_difference -> { @ws.notifications.where(kind: "budget_warning").count }, 1 do
      Budgets::CheckAlerts.call(workspace: @ws)
    end
  end

  test "fires budget_exceeded (not warning) when over the cap" do
    create(:budget, workspace: @ws, target_tag: @tag, monthly_limit_cents: 100_000)
    spend(120_000)

    Budgets::CheckAlerts.call(workspace: @ws)
    assert_equal 1, @ws.notifications.where(kind: "budget_exceeded").count
    assert_equal 0, @ws.notifications.where(kind: "budget_warning").count
  end

  test "idempotent: does not re-fire the same level in the same month" do
    create(:budget, workspace: @ws, target_tag: @tag, monthly_limit_cents: 100_000)
    spend(120_000)

    Budgets::CheckAlerts.call(workspace: @ws)
    assert_no_difference -> { @ws.notifications.count } do
      Budgets::CheckAlerts.call(workspace: @ws)
    end
  end

  test "no alert below threshold" do
    create(:budget, workspace: @ws, target_tag: @tag, monthly_limit_cents: 100_000, alert_threshold_pct: 80)
    spend(50_000)
    assert_no_difference -> { @ws.notifications.count } do
      Budgets::CheckAlerts.call(workspace: @ws)
    end
  end

  test "skips disabled budgets" do
    create(:budget, workspace: @ws, target_tag: @tag, monthly_limit_cents: 100_000, enabled: false)
    spend(120_000)
    assert_no_difference -> { @ws.notifications.count } do
      Budgets::CheckAlerts.call(workspace: @ws)
    end
  end
end
