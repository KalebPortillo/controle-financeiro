require "test_helper"

# RF22 — categoria sugerida pela IA (2ª análise, a partir das tags aceitas),
# separada das Categories reais. Só vira Category quando aceita.
class SuggestedCategoryTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
  end

  test "valid factory" do
    assert build(:suggested_category, workspace: @workspace).valid?
  end

  test "requires name" do
    sc = build(:suggested_category, workspace: @workspace, name: nil)
    assert_not sc.valid?
    assert_includes sc.errors[:name], "can't be blank"
  end

  test "name is unique per workspace (case-insensitive via citext)" do
    create(:suggested_category, workspace: @workspace, name: "Alimentação")
    dup = build(:suggested_category, workspace: @workspace, name: "alimentação")
    assert_not dup.valid?
  end

  test "same name allowed across workspaces" do
    create(:suggested_category, workspace: @workspace, name: "Alimentação")
    other = build(:suggested_category, workspace: create(:workspace), name: "Alimentação")
    assert other.valid?
  end

  test "status defaults to pending" do
    assert_equal "pending", create(:suggested_category, workspace: @workspace).status
  end

  test "rejects invalid status" do
    assert_not build(:suggested_category, workspace: @workspace, status: "bogus").valid?
  end

  test "stores tag_names as an array" do
    sc = create(:suggested_category, workspace: @workspace, tag_names: [ "Mercado", "Padaria" ])
    assert_equal [ "Mercado", "Padaria" ], sc.reload.tag_names
  end

  test "pending scope returns only pending" do
    pending = create(:suggested_category, workspace: @workspace, name: "A")
    create(:suggested_category, workspace: @workspace, name: "B", status: "accepted")
    assert_equal [ pending.id ], @workspace.suggested_categories.pending.pluck(:id)
  end

  test ".record upserts pending, never duplicates an existing real category" do
    create(:category, workspace: @workspace, name: "Alimentação")
    result = SuggestedCategory.record(workspace: @workspace, name: "Alimentação", tag_names: [ "Mercado" ])
    assert_nil result
    assert_empty @workspace.suggested_categories
  end

  test ".record does not resurrect an accepted/dismissed suggestion" do
    create(:suggested_category, workspace: @workspace, name: "Lazer", status: "accepted")
    SuggestedCategory.record(workspace: @workspace, name: "Lazer", tag_names: [])
    assert_equal "accepted", @workspace.suggested_categories.find_by(name: "Lazer").status
  end
end
