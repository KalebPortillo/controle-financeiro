require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "factory builds a valid account" do
    assert build(:account).valid?
  end

  test "requires workspace, name, kind, institution" do
    account = Account.new
    assert_not account.valid?
    assert_includes account.errors[:workspace], "must exist"
    assert_includes account.errors[:name],      "can't be blank"
  end

  test "owner_membership is optional (nullified when member is removed)" do
    account = build(:account, owner_membership: nil)
    account.valid?
    assert_empty account.errors[:owner_membership]
  end

  test "kind must be checking or credit_card" do
    account = build(:account, kind: "bogus")
    assert_not account.valid?
    assert_includes account.errors[:kind], "is not included in the list"
  end

  test "institution must be in the allowed set" do
    account = build(:account, institution: "bogus")
    assert_not account.valid?
    assert_includes account.errors[:institution], "is not included in the list"
  end

  test "currency defaults to BRL" do
    assert_equal "BRL", Account.new.currency
  end

  test "bank_connection is optional (manual account)" do
    account = build(:account, bank_connection: nil, institution: "manual")
    assert account.valid?
  end

  test "external_id is unique per bank_connection when present" do
    conn = create(:bank_connection)
    create(:account, bank_connection: conn, workspace: conn.workspace, external_id: "acc-1")
    dup = build(:account, bank_connection: conn, workspace: conn.workspace, external_id: "acc-1")
    assert_not dup.valid?
    assert_includes dup.errors[:external_id], "has already been taken"
  end

  test "kind helpers" do
    assert build(:account, kind: "checking").checking?
    assert build(:account, kind: "credit_card").credit_card?
  end
end
