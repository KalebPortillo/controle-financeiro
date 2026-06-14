require "test_helper"

# Backfill que conserta grupos de parcelamento inconsistentes em produção.
class Transactions::RegroupInstallmentsTest < ActiveSupport::TestCase
  setup do
    @account = create(:account)
    @ws = @account.workspace
  end

  def cc(purchase_date:, number:, total:, mcc: 5999, card: "5190")
    meta = { "cardNumber" => card, "purchaseDate" => purchase_date,
             "installmentNumber" => number, "totalInstallments" => total }
    meta["payeeMCC"] = mcc if mcc
    { "id" => "plg-#{SecureRandom.hex(4)}", "creditCardMetadata" => meta }
  end

  def parcel(desc:, number:, total:, purchase_date:, occurred:, mcc: 5999, status: "pending", group: "legacy")
    create(:transaction, account: @account, workspace: @ws, original_description: desc,
           installment_number: number, installment_total: total, status: status,
           occurred_at: occurred, installment_group_id: group,
           source_metadata: cc(purchase_date: purchase_date, number: number, total: total, mcc: mcc))
  end

  test "separa compras distintas no mesmo lugar+total que colidiam num grupo só" do
    # Duas compras 10x no mesmo estabelecimento, purchaseDate diferente, mesmo
    # group_id legado.
    a = parcel(desc: "SAO JORGE 8/10", number: 8, total: 10, purchase_date: "2025-09-25T13:05:38.001Z", occurred: Date.new(2026, 4, 3))
    b = parcel(desc: "SAO JORGE 8/10", number: 8, total: 10, purchase_date: "2025-09-29T18:39:58.001Z", occurred: Date.new(2026, 4, 3))

    result = Transactions::RegroupInstallments.call(scope: @ws.transactions)

    assert_equal 2, result[:regrouped]
    assert_not_equal a.reload.installment_group_id, b.reload.installment_group_id
  end

  test "mantém parcelas da mesma compra no mesmo grupo" do
    p1 = parcel(desc: "LOJA 1/4", number: 1, total: 4, purchase_date: "2026-05-30T03:05:01.001Z", occurred: Date.new(2026, 5, 30))
    p2 = parcel(desc: "LOJA 2/4", number: 2, total: 4, purchase_date: "2026-05-30T03:05:01.001Z", occurred: Date.new(2026, 6, 30))

    Transactions::RegroupInstallments.call(scope: @ws.transactions)

    assert_equal p1.reload.installment_group_id, p2.reload.installment_group_id
  end

  test "remove parcela projetada duplicada quando há a canônica" do
    canonical = parcel(desc: "MERCADOLIVRE LIVIAARTS 3/4", number: 3, total: 4,
                       purchase_date: "2026-05-30T03:05:01.001Z", occurred: Date.new(2026, 7, 30))
    projected = parcel(desc: "Mercadolivre Liviaarts 3/4", number: 3, total: 4, mcc: nil,
                       purchase_date: "2026-07-31T00:00:00.001Z", occurred: Date.new(2026, 7, 31))

    result = Transactions::RegroupInstallments.call(scope: @ws.transactions)

    assert_equal 1, result[:removed]
    assert Transaction.exists?(canonical.id), "a parcela canônica permanece"
    assert_not Transaction.exists?(projected.id), "a projetada é removida"
  end

  test "não remove projetada se não houver canônica (evita apagar legítima)" do
    lonely = parcel(desc: "LOJA X 2/3", number: 2, total: 3, mcc: nil,
                    purchase_date: "2026-07-31T00:00:00.001Z", occurred: Date.new(2026, 7, 31))

    result = Transactions::RegroupInstallments.call(scope: @ws.transactions)

    assert_equal 0, result[:removed]
    assert Transaction.exists?(lonely.id)
  end

  test "não remove parcela consolidada (já revisada pelo usuário)" do
    parcel(desc: "ML 3/4", number: 3, total: 4, purchase_date: "2026-05-30T03:05:01.001Z", occurred: Date.new(2026, 7, 30))
    consolidated_dup = parcel(desc: "ML 3/4", number: 3, total: 4, mcc: nil, status: "consolidated",
                              purchase_date: "2026-07-31T00:00:00.001Z", occurred: Date.new(2026, 7, 31))

    result = Transactions::RegroupInstallments.call(scope: @ws.transactions)

    assert_equal 0, result[:removed]
    assert Transaction.exists?(consolidated_dup.id)
  end

  test "idempotente: rodar de novo não muda nada" do
    parcel(desc: "SAO JORGE 8/10", number: 8, total: 10, purchase_date: "2025-09-25T13:05:38.001Z", occurred: Date.new(2026, 4, 3))
    parcel(desc: "SAO JORGE 8/10", number: 8, total: 10, purchase_date: "2025-09-29T18:39:58.001Z", occurred: Date.new(2026, 4, 3))

    Transactions::RegroupInstallments.call(scope: @ws.transactions)
    second = Transactions::RegroupInstallments.call(scope: @ws.transactions)

    assert_equal({ regrouped: 0, removed: 0 }, second)
  end
end
