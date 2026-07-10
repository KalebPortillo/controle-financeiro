require "test_helper"

# RF10.6 — heurística de confiança pra casar estorno (credit) → gasto original.
# Alta: nome/código único (casa mesmo com valor diferente). Média: nome genérico
# + valor exato único. Baixa (nil): nome genérico + valor diferente → fica solto.
class Refunds::MatchTest < ActiveSupport::TestCase
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

  def with_iof(purchase:, iof_cents:)
    iof = debit(description: "IOF de compra internacional", amount_cents: iof_cents)
    create(:transaction_link, workspace: @workspace, primary_transaction: purchase,
           related_transaction: iof, relation_type: "iof")
    iof
  end

  # --- alta confiança: nome/código único ------------------------------------

  test "código único casa com ALTA confiança, mesmo valor diferente (parcial)" do
    purchase = debit(description: "AMAZON RETA PZ7SW7MV3", amount_cents: 103_000)
    c = credit(description: 'Crédito de "AMAZON RETA* PZ7SW7MV3"', amount_cents: 5918)

    r = Refunds::Match.call(credit: c)
    assert_equal purchase.id, r.debit.id
    assert_equal :high, r.confidence
  end

  test "nome exato (código) ganha de débitos genéricos da mesma loja (não vira ambíguo)" do
    purchase = debit(description: "Amazon Reta* Pz7sw7mv3", amount_cents: 103_000)
    debit(description: "Amazon", amount_cents: 4696)
    debit(description: "Amazon", amount_cents: 4421)
    c = credit(description: 'Estorno de "AMAZON RETA* PZ7SW7MV3"', amount_cents: 23_676)

    r = Refunds::Match.call(credit: c)
    assert_equal purchase.id, r.debit.id
    assert_equal :high, r.confidence
  end

  test "nome único (sem código) casa com ALTA confiança mesmo com valor diferente (Nike)" do
    purchase = debit(description: "Nike US Stores", amount_cents: 50_000)
    debit(description: "Padaria do Zé", amount_cents: 44_938) # ruído
    c = credit(description: 'Estorno de "Nike US Stores"', amount_cents: 44_938)

    r = Refunds::Match.call(credit: c)
    assert_equal purchase.id, r.debit.id
    assert_equal :high, r.confidence
  end

  # --- média confiança: nome genérico + valor exato -------------------------

  test "nome genérico + valor exato único casa com MÉDIA confiança" do
    purchase = debit(description: "Compra avulsa", amount_cents: 7777)
    c = credit(description: "Estorno recebido", amount_cents: 7777)

    r = Refunds::Match.call(credit: c)
    assert_equal purchase.id, r.debit.id
    assert_equal :medium, r.confidence
  end

  test "nome ambíguo (2 gastos) desempata pelo valor exato → ALTA" do
    debit(description: "Nike US Stores", amount_cents: 50_000)
    exact = debit(description: "Nike US Stores", amount_cents: 44_938)
    c = credit(description: 'Estorno de "Nike US Stores"', amount_cents: 44_938)

    r = Refunds::Match.call(credit: c)
    assert_equal exact.id, r.debit.id
    assert_equal :high, r.confidence
  end

  # --- baixa: nome genérico + valor diferente → solto -----------------------

  test "nome genérico + valor diferente → nil (fica solto)" do
    debit(description: "Compra avulsa", amount_cents: 9999)
    c = credit(description: "Estorno recebido", amount_cents: 5000)

    assert_nil Refunds::Match.call(credit: c)
  end

  test "nome ambíguo sem valor exato → nil" do
    debit(description: "Nike US Stores", amount_cents: 50_000)
    debit(description: "Nike US Stores", amount_cents: 60_000)
    c = credit(description: 'Estorno de "Nike US Stores"', amount_cents: 44_938)

    assert_nil Refunds::Match.call(credit: c)
  end

  # --- portão: só estornos --------------------------------------------------

  test "crédito que não parece estorno (salário) → nil" do
    debit(description: "Compra avulsa", amount_cents: 800_000)
    c = credit(description: "Pagamento de salário", amount_cents: 800_000)

    assert_nil Refunds::Match.call(credit: c)
  end

  # --- IOF: nome do comerciante ---------------------------------------------

  test "estorno de IOF por comerciante (hellenika) → ALTA, alvo é o débito de IOF" do
    purchase = debit(description: "Sq *Hellenika Cultured", amount_cents: 4233)
    iof = with_iof(purchase: purchase, iof_cents: 148)
    c = credit(description: "IOF de volta de Sq *Hellenika Cultured", amount_cents: 148)

    r = Refunds::Match.call(credit: c)
    assert_equal iof.id, r.debit.id
    assert_equal :high, r.confidence
  end

  test "estorno de IOF genérico (sem comerciante) + valor exato único → MÉDIA" do
    iof = debit(description: "IOF de compra internacional", amount_cents: 329)
    c = credit(description: "Estorno de IOF de compra internacional", amount_cents: 329)

    r = Refunds::Match.call(credit: c)
    assert_equal iof.id, r.debit.id
    assert_equal :medium, r.confidence
  end

  test "estorno de IOF genérico com valor que casa 2 IOFs → nil (ambíguo)" do
    debit(description: "IOF de compra internacional", amount_cents: 329)
    debit(description: "IOF de compra internacional", amount_cents: 329)
    c = credit(description: "Estorno de IOF de compra internacional", amount_cents: 329)

    assert_nil Refunds::Match.call(credit: c)
  end

  test "só age sobre créditos" do
    assert_nil Refunds::Match.call(credit: debit(description: "X AB12CD34"))
  end
end
