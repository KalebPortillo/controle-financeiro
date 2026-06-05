require "test_helper"

# RF20 — processamento de um import: parseia o arquivo e cria as transações na
# inbox, com dedup. Anexa e processa na mesma transação (sem cruzar requests),
# evitando o cleanup do Active Storage de testes.
class Imports::ProcessTest < ActiveSupport::TestCase
  setup do
    @workspace  = create(:workspace)
    @membership = create(:workspace_membership, workspace: @workspace)
  end

  def import_with(csv)
    imp = @workspace.imports.create!(uploaded_by_membership: @membership,
                                     filename: "x.csv", format: "csv", file_size_bytes: csv.bytesize)
    imp.file.attach(io: StringIO.new(csv), filename: "x.csv", content_type: "text/csv")
    imp
  end

  VALID = "data,descricao,valor\n01/01/2026,MERCADO,-50.00\n02/01/2026,SALARIO,1000.00\n".freeze

  test "creates pending manual_import transactions in the inbox" do
    imp = import_with(VALID)
    Imports::Process.call(import: imp)

    assert_equal "completed", imp.reload.status
    assert_equal 2, imp.created_count
    txs = @workspace.transactions.where(status: "pending", source: "manual_import")
    assert_equal 2, txs.count
    debit = txs.find_by(direction: "debit")
    assert_equal 5_000, debit.amount_cents
    assert_equal Date.new(2026, 1, 1), debit.occurred_at
  end

  test "uses the manual account when the import has none" do
    imp = import_with(VALID)
    Imports::Process.call(import: imp)
    assert @workspace.accounts.exists?(institution: "manual")
  end

  test "uses the import account when provided" do
    account = create(:account, workspace: @workspace)
    imp = import_with(VALID)
    imp.update!(account: account)
    Imports::Process.call(import: imp)
    assert_equal 2, account.transactions.count
  end

  test "deduplicates rows that were already imported" do
    Imports::Process.call(import: import_with(VALID))
    second = import_with(VALID)
    Imports::Process.call(import: second)

    assert_equal 2, @workspace.transactions.count
    assert_equal 0, second.reload.created_count
    assert_equal 2, second.duplicate_count
  end

  test "a malformed row is counted as error, not fatal" do
    imp = import_with("data,descricao,valor\n01/01/2026,OK,-10.00\nzzz,BAD,abc\n")
    Imports::Process.call(import: imp)
    assert_equal 1, imp.reload.created_count
    assert_equal 1, imp.error_count
    assert imp.error_log.any?
  end

  test "fails gracefully on an unsupported format" do
    imp = import_with(VALID)
    imp.update_column(:format, "ofx")
    Imports::Process.call(import: imp)
    assert_equal "failed", imp.reload.status
  end
end
