require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "factory builds a valid transaction" do
    assert build(:transaction).valid?
  end

  test "muda de status → broadcasta no TransactionsChannel do workspace (tempo real)" do
    tx = create(:transaction, status: "pending")

    assert_broadcasts(TransactionsChannel.broadcasting_for(tx.workspace), 1) do
      tx.update!(status: "consolidated", consolidated_at: Time.current)
    end
  end

  test "editar sem mexer no status NÃO broadcasta" do
    tx = create(:transaction, status: "pending")

    assert_no_broadcasts(TransactionsChannel.broadcasting_for(tx.workspace)) do
      tx.update!(improved_title: "Novo título")
    end
  end

  test "requires workspace, account, direction, amount_cents, occurred_at, original_description" do
    txn = Transaction.new
    assert_not txn.valid?
    assert_includes txn.errors[:account],              "must exist"
    assert_includes txn.errors[:amount_cents],         "can't be blank"
    assert_includes txn.errors[:occurred_at],          "can't be blank"
    assert_includes txn.errors[:original_description], "can't be blank"
  end

  test "direction must be debit or credit" do
    assert_not build(:transaction, direction: "bogus").valid?
  end

  test "amount_cents must be positive" do
    txn = build(:transaction, amount_cents: 0)
    assert_not txn.valid?
    assert_includes txn.errors[:amount_cents], "must be greater than 0"
  end

  test "status defaults to pending (inbox)" do
    assert_equal "pending", Transaction.new.status
  end

  test "status must be in the allowed set" do
    assert_not build(:transaction, status: "bogus").valid?
  end

  test "source must be in the allowed set" do
    assert_not build(:transaction, source: "bogus").valid?
  end

  test "currency defaults to BRL" do
    assert_equal "BRL", Transaction.new.currency
  end

  test "external_transaction_id is generated from source_metadata id" do
    txn = create(:transaction, source_metadata: { "id" => "pluggy-tx-42" })
    assert_equal "pluggy-tx-42", txn.reload.external_transaction_id
  end

  test "(account_id, external_transaction_id) is unique — dedup de sync" do
    account = create(:account)
    create(:transaction, account: account, workspace: account.workspace,
                         source_metadata: { "id" => "dup-1" })
    dup = build(:transaction, account: account, workspace: account.workspace,
                              source_metadata: { "id" => "dup-1" })
    # external_transaction_id é coluna GERADA — unicidade é garantida no DB,
    # então a violação vem como exceção (não como validação de model).
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save }
  end

  test "status helpers" do
    assert build(:transaction, status: "pending").pending?
    assert build(:transaction, status: "consolidated").consolidated?
  end

  test "scopes: inbox (pending) e consolidated" do
    account = create(:account)
    ws = account.workspace
    pend = create(:transaction, account: account, workspace: ws, status: "pending",
                               source_metadata: { "id" => "p1" })
    cons = create(:transaction, account: account, workspace: ws, status: "consolidated",
                               source_metadata: { "id" => "c1" }, consolidated_at: Time.current)
    assert_includes Transaction.inbox, pend
    assert_not_includes Transaction.inbox, cons
    assert_includes Transaction.consolidated, cons
  end
end
