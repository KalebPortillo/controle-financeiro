require "test_helper"

# RF9.4 — parsing de parcelamento do cartão a partir do payload do agregador.
class Transactions::InstallmentTest < ActiveSupport::TestCase
  def parse(raw: nil, description: nil)
    Transactions::Installment.parse(raw: raw, description: description)
  end

  test "lê do creditCardMetadata do Pluggy" do
    info = parse(raw: { "creditCardMetadata" => { "installmentNumber" => 3, "totalInstallments" => 12 } },
                 description: "GELADEIRA")
    assert_equal 3, info.number
    assert_equal 12, info.total
  end

  test "fallback: lê da descrição '3/12'" do
    info = parse(description: "GELADEIRA 3/12")
    assert_equal 3, info.number
    assert_equal 12, info.total
  end

  test "fallback: descrição 'PARCELA 03/12'" do
    info = parse(description: "MAGAZINE PARCELA 03/12")
    assert_equal 3, info.number
    assert_equal 12, info.total
  end

  test "metadata tem precedência sobre a descrição" do
    info = parse(raw: { "creditCardMetadata" => { "installmentNumber" => 2, "totalInstallments" => 6 } },
                 description: "COISA 3/12")
    assert_equal 2, info.number
    assert_equal 6, info.total
  end

  test "nil quando não há parcelamento" do
    assert_nil parse(description: "PADARIA IPIRANGA")
    assert_nil parse(raw: { "id" => "x" }, description: "MERCADO")
  end

  test "nil quando total < 2 (compra à vista, não é parcelamento)" do
    assert_nil parse(raw: { "creditCardMetadata" => { "installmentNumber" => 1, "totalInstallments" => 1 } },
                     description: "À VISTA")
  end

  test "nil quando number > total (provável data, ex. '12/05')" do
    assert_nil parse(description: "COMPRA 12/05")
  end

  test "group_id é determinístico por (conta, descritor, total) — fallback sem purchaseDate" do
    a = Transactions::Installment.group_id(account_id: "acc-1", description: "GELADEIRA 3/12", total: 12)
    b = Transactions::Installment.group_id(account_id: "acc-1", description: "GELADEIRA 4/12", total: 12)
    c = Transactions::Installment.group_id(account_id: "acc-1", description: "GELADEIRA 3/12", total: 10)
    assert_equal a, b, "parcelas da mesma compra → mesmo group_id"
    assert_not_equal a, c, "total diferente → group_id diferente"
    assert_match(/\A[0-9a-f-]{36}\z/, a)
  end

  # A data da COMPRA é retro-calculada da parcela (occurred − (número−1) meses),
  # NÃO lida do `purchaseDate`: o Pluggy emite purchaseDate SINTÉTICO (= data da
  # fatura) nas parcelas futuras/projetadas, o que fragmentava a compra em vários
  # grupos. Retro-calcular cola todas as parcelas e distingue compras por data+total.
  test "group_id cola parcelas da mesma compra (occurred+número → mesma data)" do
    a = Transactions::Installment.group_id(account_id: "acc-1", description: "LOJA 7/10", total: 10,
                                           number: 7, occurred: Date.new(2026, 4, 13))
    b = Transactions::Installment.group_id(account_id: "acc-1", description: "LOJA 8/10", total: 10,
                                           number: 8, occurred: Date.new(2026, 5, 13))
    assert_equal a, b, "parcelas 7 e 8 da mesma compra (out/2025) → mesmo group_id"
  end

  # Regressão do bug real (Vivoeasyanual): a parcela canônica traz purchaseDate
  # real e as projetadas trazem purchaseDate sintético; mesmo assim colam, porque
  # o anchor ignora purchaseDate e usa occurred+número.
  test "group_id cola parcela canônica e projetada da mesma compra" do
    canonical = Transactions::Installment.group_id(account_id: "acc-1", description: "LITE VIVO 1/12",
                                                   total: 12, number: 1, occurred: Date.new(2026, 6, 9))
    projected = Transactions::Installment.group_id(account_id: "acc-1", description: "LITE VIVO 2/12",
                                                   total: 12, number: 2, occurred: Date.new(2026, 7, 9))
    assert_equal canonical, projected, "1/12 e 2/12 (jun/2026) → mesmo group_id"
  end

  test "group_id separa compras distintas no mesmo lugar+total por data de compra" do
    same_desc = "SAO JORGE SHOPPING 8/10"
    a = Transactions::Installment.group_id(account_id: "acc-1", description: same_desc, total: 10,
                                           number: 8, occurred: Date.new(2026, 4, 25))
    b = Transactions::Installment.group_id(account_id: "acc-1", description: same_desc, total: 10,
                                           number: 8, occurred: Date.new(2026, 4, 29))
    assert_not_equal a, b, "compras 4 dias distintas → grupos diferentes"
  end

  test "projected?: purchaseDate sintético (meia-noite = própria data) sem MCC" do
    raw = { "creditCardMetadata" => { "purchaseDate" => "2026-07-31T00:00:00.001Z", "installmentNumber" => 3, "totalInstallments" => 4 } }
    assert Transactions::Installment.projected?(raw, Date.new(2026, 7, 31))
  end

  test "projected?: false quando purchaseDate é real (tem hora)" do
    raw = { "creditCardMetadata" => { "purchaseDate" => "2026-05-30T03:05:01.001Z", "payeeMCC" => 5999, "installmentNumber" => 3, "totalInstallments" => 4 } }
    assert_not Transactions::Installment.projected?(raw, Date.new(2026, 7, 30))
  end

  test "projected?: false quando há payeeMCC mesmo à meia-noite" do
    raw = { "creditCardMetadata" => { "purchaseDate" => "2026-07-31T00:00:00.001Z", "payeeMCC" => 5999 } }
    assert_not Transactions::Installment.projected?(raw, Date.new(2026, 7, 31))
  end

  test "projected?: false sem metadata/purchaseDate" do
    assert_not Transactions::Installment.projected?({ "id" => "x" }, Date.new(2026, 7, 31))
    assert_not Transactions::Installment.projected?(nil, Date.new(2026, 7, 31))
  end
end
