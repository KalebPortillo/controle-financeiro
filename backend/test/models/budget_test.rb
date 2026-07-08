require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  setup do
    @ws  = create(:workspace)
    @tag = create(:tag, workspace: @ws)
  end

  test "valid tag budget" do
    b = build(:budget, workspace: @ws, target_tag: @tag)
    assert b.valid?, b.errors.full_messages.to_sentence
  end

  test "rejects non-positive limit" do
    b = build(:budget, workspace: @ws, target_tag: @tag, monthly_limit_cents: 0)
    assert_not b.valid?
  end

  test "rejects alert threshold out of range" do
    assert_not build(:budget, workspace: @ws, target_tag: @tag, alert_threshold_pct: 0).valid?
    assert_not build(:budget, workspace: @ws, target_tag: @tag, alert_threshold_pct: 101).valid?
  end

  test "tag budget requires target_tag and forbids target_category" do
    assert_not build(:budget, workspace: @ws, kind: "tag", target_tag: nil).valid?
    cat = create(:category, workspace: @ws)
    assert_not build(:budget, workspace: @ws, kind: "tag", target_tag: @tag, target_category: cat).valid?
  end

  test "category budget requires target_category" do
    b = build(:budget, :category, workspace: @ws)
    assert b.valid?, b.errors.full_messages.to_sentence
    assert_not build(:budget, kind: "category", workspace: @ws, target_category: nil, target_tag: nil).valid?
  end

  test "composite budget forbids both targets" do
    b = build(:budget, :composite, workspace: @ws)
    assert b.valid?, b.errors.full_messages.to_sentence
  end

  test "target must be in same workspace" do
    other_tag = create(:tag, workspace: create(:workspace))
    assert_not build(:budget, workspace: @ws, kind: "tag", target_tag: other_tag).valid?
  end

  test "tracked_tag_ids resolves per kind" do
    tag_budget = create(:budget, workspace: @ws, target_tag: @tag)
    assert_equal [ @tag.id ], tag_budget.tracked_tag_ids

    t1 = create(:tag, workspace: @ws)
    t2 = create(:tag, workspace: @ws)
    cat = create(:category, workspace: @ws, tags: [ t1, t2 ])
    cat_budget = create(:budget, :category, workspace: @ws, target_category: cat)
    assert_equal [ t1.id, t2.id ].sort, cat_budget.tracked_tag_ids.sort

    comp = create(:budget, :composite, workspace: @ws, composite_tags: [ t1 ])
    assert_equal [ t1.id ], comp.tracked_tag_ids
  end

  test "active_on filters by window and enabled" do
    inside  = create(:budget, workspace: @ws, target_tag: @tag, starts_on: Date.new(2026, 6, 1), ends_on: Date.new(2026, 6, 30))
    _off    = create(:budget, workspace: @ws, target_tag: create(:tag, workspace: @ws), enabled: false)
    _future = create(:budget, workspace: @ws, target_tag: create(:tag, workspace: @ws), starts_on: Date.new(2026, 7, 1))

    active = @ws.budgets.active_on(Date.new(2026, 6, 15))
    assert_includes active, inside
    assert_not_includes active, _off
    assert_not_includes active, _future
  end
end
