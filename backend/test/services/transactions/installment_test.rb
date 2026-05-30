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

  test "group_id é determinístico por (conta, descritor, total)" do
    a = Transactions::Installment.group_id(account_id: "acc-1", description: "GELADEIRA 3/12", total: 12)
    b = Transactions::Installment.group_id(account_id: "acc-1", description: "GELADEIRA 4/12", total: 12)
    c = Transactions::Installment.group_id(account_id: "acc-1", description: "GELADEIRA 3/12", total: 10)
    assert_equal a, b, "parcelas da mesma compra → mesmo group_id"
    assert_not_equal a, c, "total diferente → group_id diferente"
    assert_match(/\A[0-9a-f-]{36}\z/, a)
  end
end
