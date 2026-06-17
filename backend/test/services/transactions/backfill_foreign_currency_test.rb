require "test_helper"

class Transactions::BackfillForeignCurrencyTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace, currency: "BRL")
  end

  def tx(**attrs)
    create(:transaction, **{ workspace: @workspace, account: @account, status: "pending" }.merge(attrs))
  end

  test "converte gasto em USD usando amountInAccountCurrency (valor nominal vira BRL)" do
    usd = tx(amount_cents: 40000, currency: "USD", # entrou errado: US$ 400 como se fosse R$ 400
             source_metadata: { "id" => "u1", "currencyCode" => "USD", "amountInAccountCurrency" => 2189.59 })

    result = Transactions::BackfillForeignCurrency.call

    usd.reload
    assert_equal 218959, usd.amount_cents
    assert_equal "BRL", usd.currency
    assert_equal 1, result[:fixed]
  end

  test "não toca em gasto em BRL" do
    brl = tx(amount_cents: 5000, currency: "BRL",
             source_metadata: { "id" => "b1", "currencyCode" => "BRL" })

    Transactions::BackfillForeignCurrency.call

    assert_equal 5000, brl.reload.amount_cents
  end

  test "ignora quando não há amountInAccountCurrency" do
    odd = tx(amount_cents: 40000, currency: "USD",
             source_metadata: { "id" => "x1", "currencyCode" => "USD" })

    result = Transactions::BackfillForeignCurrency.call

    assert_equal 40000, odd.reload.amount_cents # sem o valor convertido, não dá pra arrumar
    assert_equal 0, result[:fixed]
  end

  test "idempotente: segunda execução não altera nada" do
    tx(amount_cents: 40000, currency: "USD",
       source_metadata: { "id" => "u1", "currencyCode" => "USD", "amountInAccountCurrency" => 2189.59 })

    Transactions::BackfillForeignCurrency.call
    result = Transactions::BackfillForeignCurrency.call

    assert_equal 0, result[:fixed]
    assert_equal 1, result[:skipped]
  end
end
