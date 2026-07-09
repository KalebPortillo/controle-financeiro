require "test_helper"

# RF10.6 — casa um estorno (credit) ao gasto original por CÓDIGO exato presente
# no nome. Só devolve match quando é ÚNICO; genérico/ambíguo → nil (fica só
# como sugestão on-demand).
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
    debit(description: "OUTRA COMPRA ZZ99YY00", amount_cents: 5000)
    c = credit(description: "ESTORNO AB12CD34")

    assert_equal match.id, Refunds::CodeMatch.call(credit: c).id
  end

  test "código que casa mais de um gasto → nil (ambíguo)" do
    debit(description: "COMPRA AB12CD34 UM", amount_cents: 5000)
    debit(description: "COMPRA AB12CD34 DOIS", amount_cents: 4900) # dentro da tolerância
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

  test "ignora gasto fora da janela de valor (não é candidato)" do
    debit(description: "COMPRA AB12CD34", amount_cents: 20_000) # bem diferente do crédito
    c = credit(description: "ESTORNO AB12CD34", amount_cents: 5000)

    assert_nil Refunds::CodeMatch.call(credit: c)
  end

  test "só age sobre créditos" do
    d = debit(description: "COMPRA AB12CD34")
    assert_nil Refunds::CodeMatch.call(credit: d)
  end
end
