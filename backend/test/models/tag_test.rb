require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "factory builds a valid tag" do
    assert build(:tag).valid?
  end

  test "requires workspace and name" do
    tag = Tag.new
    assert_not tag.valid?
    assert_includes tag.errors[:workspace], "must exist"
    assert_includes tag.errors[:name], "can't be blank"
  end

  test "name é único por workspace (case-insensitive)" do
    ws = create(:workspace)
    create(:tag, workspace: ws, name: "Mercado")
    dup = build(:tag, workspace: ws, name: "mercado")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  test "mesmo nome em workspaces diferentes é permitido" do
    create(:tag, workspace: create(:workspace), name: "Mercado")
    other = build(:tag, workspace: create(:workspace), name: "Mercado")
    assert other.valid?
  end

  test "aplica e remove tags numa transação (M:N)" do
    ws = create(:workspace)
    account = create(:account, workspace: ws)
    t = create(:transaction, workspace: ws, account: account)
    tag = create(:tag, workspace: ws)

    t.tags << tag
    assert_includes t.reload.tags, tag
    assert_includes tag.reload.transactions, t
  end
end
