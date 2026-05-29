require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "factory builds a valid category" do
    assert build(:category).valid?
  end

  test "requires workspace and name" do
    c = Category.new
    assert_not c.valid?
    assert_includes c.errors[:workspace], "must exist"
    assert_includes c.errors[:name], "can't be blank"
  end

  test "name único por workspace (case-insensitive)" do
    ws = create(:workspace)
    create(:category, workspace: ws, name: "Alimentação")
    dup = build(:category, workspace: ws, name: "alimentação")
    assert_not dup.valid?
  end

  test "agrega tags (M:N) e uma tag pode estar em N categorias (RF6.2)" do
    ws = create(:workspace)
    tag = create(:tag, workspace: ws, name: "Padaria")
    c1 = create(:category, workspace: ws, name: "Alimentação")
    c2 = create(:category, workspace: ws, name: "Pequenos prazeres")
    c1.tags << tag
    c2.tags << tag
    assert_includes c1.reload.tags, tag
    assert_includes c2.reload.tags, tag
    assert_equal 2, tag.reload.categories.count
  end
end
