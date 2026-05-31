require "test_helper"

# RF3/RF22 — catálogo de tags sugeridas pela IA, separado das tags reais (aceitas).
# Uma sugestão só vira Tag de verdade quando aceita (onboarding, página de tags ou inbox).
class SuggestedTagTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
  end

  test "valid factory" do
    assert build(:suggested_tag, workspace: @workspace).valid?
  end

  test "requires name" do
    st = build(:suggested_tag, workspace: @workspace, name: nil)
    assert_not st.valid?
    assert_includes st.errors[:name], "can't be blank"
  end

  test "name is unique per workspace (case-insensitive via citext)" do
    create(:suggested_tag, workspace: @workspace, name: "Mercado")
    dup = build(:suggested_tag, workspace: @workspace, name: "mercado")
    assert_not dup.valid?
  end

  test "same name allowed across workspaces" do
    create(:suggested_tag, workspace: @workspace, name: "Mercado")
    other = build(:suggested_tag, workspace: create(:workspace), name: "Mercado")
    assert other.valid?
  end

  test "status defaults to pending" do
    assert_equal "pending", create(:suggested_tag, workspace: @workspace).status
  end

  test "rejects invalid status" do
    st = build(:suggested_tag, workspace: @workspace, status: "bogus")
    assert_not st.valid?
  end

  test "rejects invalid source" do
    st = build(:suggested_tag, workspace: @workspace, source: "bogus")
    assert_not st.valid?
  end

  test "pending scope returns only pending suggestions" do
    pending  = create(:suggested_tag, workspace: @workspace, name: "A", status: "pending")
    create(:suggested_tag, workspace: @workspace, name: "B", status: "accepted")
    create(:suggested_tag, workspace: @workspace, name: "C", status: "dismissed")
    assert_equal [ pending.id ], @workspace.suggested_tags.pending.pluck(:id)
  end
end
