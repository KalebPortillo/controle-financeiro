require "test_helper"

# RF10.6 — casa um estorno (credit) ao gasto original por CÓDIGO exato presente
# no nome, independente do valor (estorno parcial / "IOF de volta"). Só devolve
# match quando é ÚNICO; genérico/ambíguo → nil (fica só como sugestão).
class Refunds::CodeMatchTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
  end

  def debit(description:, amount_cents: 5000, on: Date.new(2026, 6, 1))
    create(:transaction, workspace: @workspace, account: @account, direction: "debit",
           status: "consolidated", consolidated_at: Time.current,
           original_description: description, amount_cents: amount_cents, occurred_at: on)
  end

  def credit(description:, amount_cents: 5000, on: Date.new(2026, 6, 10))
    create(:transaction, workspace: @workspace, account: @account, direction: "credit",
           status: "pending", original_description: description, amount_cents: amount_cents, occurred_at: on)
  end

  test "código exato único devolve o gasto" do
    match = debit(description: "COMPRA AB12CD34 LOJA")
    debit(description: "OUTRA COMPRA ZZ99YY00")
    c = credit(description: "ESTORNO AB12CD34")

    assert_equal match.id, Refunds::CodeMatch.call(credit: c).id
  end

  test "código único casa mesmo com valor bem diferente (estorno parcial)" do
    # Gasto de R$1030 estornado em pedaços — o código manda, não o valor.
    purchase = debit(description: "AMAZON RETA PZ7SW7MV3", amount_cents: 103_000)
    partial  = credit(description: "Crédito de AMAZON RETA PZ7SW7MV3", amount_cents: 5918)

    assert_equal purchase.id, Refunds::CodeMatch.call(credit: partial).id
  end

  # Estorno de IOF: alvo é o DÉBITO de IOF (satélite RF23 da compra), valor exato.
  def with_iof(purchase:, iof_cents:)
    iof = debit(description: "IOF de compra internacional", amount_cents: iof_cents)
    create(:transaction_link, workspace: @workspace, primary_transaction: purchase,
           related_transaction: iof, relation_type: "iof")
    iof
  end

  test "estorno de IOF casa o débito de IOF da compra do código, valor exato" do
    purchase = debit(description: "Amazon Reta R98it6de3", amount_cents: 89_054)
    iof = with_iof(purchase: purchase, iof_cents: 3117)
    iof_back = credit(description: "IOF de volta de Amazon Reta R98it6de3", amount_cents: 3117)

    assert_equal iof.id, Refunds::CodeMatch.call(credit: iof_back).id
  end

  test "estorno de IOF com valor diferente do IOF cobrado → nil" do
    purchase = debit(description: "Amazon Reta R98it6de3", amount_cents: 89_054)
    with_iof(purchase: purchase, iof_cents: 3117)
    iof_back = credit(description: "IOF de volta de Amazon Reta R98it6de3", amount_cents: 9999)

    assert_nil Refunds::CodeMatch.call(credit: iof_back)
  end

  test "estorno de IOF sem satélite de IOF na compra → nil" do
    debit(description: "Amazon Reta R98it6de3", amount_cents: 89_054) # sem link de IOF
    iof_back = credit(description: "IOF de volta de Amazon Reta R98it6de3", amount_cents: 3117)

    assert_nil Refunds::CodeMatch.call(credit: iof_back)
  end

  test "estorno de IOF SEM código casa pelo comerciante (caso hellenika)" do
    purchase = debit(description: "Sq *Hellenika Cultured", amount_cents: 4233)
    iof = with_iof(purchase: purchase, iof_cents: 148)
    iof_back = credit(description: "IOF de volta de Sq *Hellenika Cultured", amount_cents: 148)

    assert_equal iof.id, Refunds::CodeMatch.call(credit: iof_back).id
  end

  test "estorno de IOF por comerciante exige valor exato do IOF" do
    purchase = debit(description: "Sq *Hellenika Cultured", amount_cents: 4233)
    with_iof(purchase: purchase, iof_cents: 148)
    iof_back = credit(description: "IOF de volta de Sq *Hellenika Cultured", amount_cents: 999)

    assert_nil Refunds::CodeMatch.call(credit: iof_back)
  end

  test "código que casa mais de um gasto → nil (ambíguo)" do
    debit(description: "COMPRA AB12CD34 UM")
    debit(description: "COMPRA AB12CD34 DOIS")
    c = credit(description: "ESTORNO AB12CD34")

    assert_nil Refunds::CodeMatch.call(credit: c)
  end

  test "sem código distintivo no estorno → nil" do
    debit(description: "COMPRA AB12CD34")
    c = credit(description: "ESTORNO RECEBIDO") # nenhum token alfanumérico com dígito

    assert_nil Refunds::CodeMatch.call(credit: c)
  end

  test "código do estorno não bate com nenhum gasto → nil" do
    debit(description: "COMPRA ZZ99YY00")
    c = credit(description: "ESTORNO AB12CD34")

    assert_nil Refunds::CodeMatch.call(credit: c)
  end

  test "ignora gasto fora da janela de data" do
    debit(description: "COMPRA AB12CD34", on: Date.new(2025, 1, 1)) # >180d antes
    c = credit(description: "ESTORNO AB12CD34", on: Date.new(2026, 6, 10))

    assert_nil Refunds::CodeMatch.call(credit: c)
  end

  test "só age sobre créditos" do
    d = debit(description: "COMPRA AB12CD34")
    assert_nil Refunds::CodeMatch.call(credit: d)
  end
end
