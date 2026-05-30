require "test_helper"

# RF9.5 — fatura do cartão como objeto derivado (sem entidade física):
# agrega transações por mês de competência e projeta meses futuros.
class Invoices::BuilderTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 5, 15)

  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace, kind: "credit_card")
  end

  def debit(desc:, cents:, on:, status: "consolidated", **extra)
    create(:transaction, workspace: @workspace, account: @account, direction: "debit",
           original_description: desc, amount_cents: cents, occurred_at: on,
           status: status, consolidated_at: (status == "consolidated" ? Time.current : nil),
           **extra)
  end

  def build(status)
    Invoices::Builder.call(account: @account, status: status, today: TODAY)
  end

  test "open: agrega débitos do mês corrente, com período e contagem" do
    debit(desc: "PADARIA", cents: 3000, on: Date.new(2026, 5, 3))
    debit(desc: "MERCADO", cents: 12000, on: Date.new(2026, 5, 20), status: "pending")
    debit(desc: "ABRIL",   cents: 9999, on: Date.new(2026, 4, 28)) # outro mês
    debit(desc: "REJEITADA", cents: 5000, on: Date.new(2026, 5, 10), status: "rejected")
    create(:transaction, workspace: @workspace, account: @account, direction: "credit",
           amount_cents: 80000, occurred_at: Date.new(2026, 5, 5), status: "consolidated",
           consolidated_at: Time.current, original_description: "ESTORNO")

    inv = build("open").sole
    assert_equal "open", inv[:status]
    assert_equal "2026-05-01", inv[:period][:from]
    assert_equal "2026-05-31", inv[:period][:to]
    assert_equal 15000, inv[:total_cents]
    assert_equal 2, inv[:transactions_count]
  end

  test "open: installments_breakdown lista as parcelas do mês" do
    gid = SecureRandom.uuid
    debit(desc: "GELADEIRA", cents: 50000, on: Date.new(2026, 5, 8),
          installment_number: 3, installment_total: 12, installment_group_id: gid)
    debit(desc: "PADARIA", cents: 3000, on: Date.new(2026, 5, 9)) # sem parcela

    inv = build("open").sole
    assert_equal 1, inv[:installments_breakdown].size
    item = inv[:installments_breakdown].first
    assert_equal gid, item[:group_id]
    assert_equal 50000, item[:amount_cents]
    assert_match "3/12", item[:label]
  end

  test "future: projeta as parcelas restantes nos meses certos" do
    gid = SecureRandom.uuid
    debit(desc: "GELADEIRA", cents: 50000, on: Date.new(2026, 5, 8),
          installment_number: 3, installment_total: 12, installment_group_id: gid)

    invoices = build("future")
    assert_equal 3, invoices.size # jun, jul, ago
    jun = invoices.first
    assert_equal "future", jun[:status]
    assert_equal "2026-06-01", jun[:period][:from]
    assert_equal 50000, jun[:total_cents]
    assert_match "4/12", jun[:installments_breakdown].first[:label]
    assert_match "6/12", invoices.last[:installments_breakdown].first[:label]
  end

  test "future: parcelamento já encerrado (última = total) não projeta" do
    gid = SecureRandom.uuid
    debit(desc: "TV", cents: 20000, on: Date.new(2026, 5, 8),
          installment_number: 12, installment_total: 12, installment_group_id: gid)

    build("future").each { |inv| assert_empty inv[:installments_breakdown] }
  end

  test "future: recorrente mensal ativa entra em cada mês futuro" do
    create(:recurrence, workspace: @workspace, account: @account, cadence: "monthly",
           status: "active", expected_amount_cents: 5990, descriptor_pattern: "NETFLIX COM")

    invoices = build("future")
    invoices.each { |inv| assert_equal 5990, inv[:total_cents] }
    assert_equal 1, invoices.first[:transactions_count]
  end

  test "future: recorrente pausada não projeta" do
    create(:recurrence, workspace: @workspace, account: @account, cadence: "monthly",
           status: "paused", expected_amount_cents: 5990, descriptor_pattern: "PAUSADA")
    build("future").each { |inv| assert_equal 0, inv[:total_cents] }
  end
end
