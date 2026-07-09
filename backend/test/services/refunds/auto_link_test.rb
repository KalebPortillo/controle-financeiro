require "test_helper"

# RF10.6 — auto-vínculo de estorno ao gasto quando há match de código exato
# único. Aplica o estorno (origin automatic) e notifica. Idempotente.
class Refunds::AutoLinkTest < ActiveSupport::TestCase
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

  test "vincula automaticamente e reduz o valor efetivo do gasto" do
    d = debit(description: "COMPRA AB12CD34 LOJA")
    c = credit(description: "ESTORNO AB12CD34")

    assert_equal 1, Refunds::AutoLink.call(workspace: @workspace)

    refund = TransactionRefund.sole
    assert refund.automatic?
    assert_nil refund.confirmed_by_membership
    assert_equal c.id, refund.refund_transaction_id
    assert_equal d.id, refund.refunded_transaction_id
    assert_equal 0, d.reload.effective_amount_cents
  end

  test "vincula estorno parcial (não-IOF) por código, valor diferente da compra" do
    purchase = debit(description: "AMAZON RETA PZ7SW7MV3", amount_cents: 103_000)
    credit(description: "Crédito de AMAZON RETA PZ7SW7MV3", amount_cents: 5918)

    assert_equal 1, Refunds::AutoLink.call(workspace: @workspace)
    assert_equal 5918, purchase.reload.refunded_amount_cents
    assert_equal 97_082, purchase.effective_amount_cents
  end

  test "vincula estorno de IOF ao débito de IOF exato da compra" do
    purchase = debit(description: "Amazon Reta R98it6de3", amount_cents: 89_054)
    iof = debit(description: "IOF de compra internacional", amount_cents: 3117)
    create(:transaction_link, workspace: @workspace, primary_transaction: purchase,
           related_transaction: iof, relation_type: "iof")
    credit(description: "IOF de volta de Amazon Reta R98it6de3", amount_cents: 3117)

    assert_equal 1, Refunds::AutoLink.call(workspace: @workspace)
    assert_equal 0, iof.reload.effective_amount_cents
    assert_equal 89_054, purchase.reload.effective_amount_cents # a compra não muda
  end

  test "é idempotente — não duplica o vínculo" do
    debit(description: "COMPRA AB12CD34")
    credit(description: "ESTORNO AB12CD34")
    Refunds::AutoLink.call(workspace: @workspace)

    assert_no_difference -> { TransactionRefund.count } do
      Refunds::AutoLink.call(workspace: @workspace)
    end
  end

  test "não vincula quando o código é ambíguo (mais de um gasto)" do
    debit(description: "COMPRA AB12CD34 UM")
    debit(description: "COMPRA AB12CD34 DOIS", amount_cents: 4900)
    credit(description: "ESTORNO AB12CD34")

    assert_equal 0, Refunds::AutoLink.call(workspace: @workspace)
    assert_equal 0, TransactionRefund.count
  end

  test "não toca em crédito já vinculado manualmente" do
    d = debit(description: "COMPRA AB12CD34")
    c = credit(description: "ESTORNO AB12CD34")
    membership = create(:workspace_membership, workspace: @workspace)
    create(:transaction_refund, refund_transaction: c, refunded_transaction: d,
           confirmed_by_membership: membership, origin: "manual")

    assert_equal 0, Refunds::AutoLink.call(workspace: @workspace)
    assert_equal 1, TransactionRefund.count
    assert_not TransactionRefund.sole.automatic?
  end

  test "gera notificação do estorno auto-vinculado" do
    debit(description: "COMPRA AB12CD34 LOJA", amount_cents: 5000)
    credit(description: "ESTORNO AB12CD34")

    assert_difference -> { @workspace.notifications.where(kind: "refund_auto_linked").count }, 1 do
      Refunds::AutoLink.call(workspace: @workspace)
    end
  end

  test "notify: false (backfill) vincula sem notificar" do
    debit(description: "COMPRA AB12CD34 LOJA", amount_cents: 5000)
    credit(description: "ESTORNO AB12CD34")

    assert_no_difference -> { @workspace.notifications.count } do
      assert_equal 1, Refunds::AutoLink.call(workspace: @workspace, notify: false)
    end
  end
end
