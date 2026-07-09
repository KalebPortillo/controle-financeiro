require "test_helper"

# RF9.1/RF9.7 — palpite de cadência/valor/próximo vencimento a partir de um
# conjunto de transações que casam um padrão. Alimenta a detecção automática e
# a criação manual semeada de um gasto.
class Recurrences::GuessTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
  end

  def tx(amount_cents:, on:)
    build(:transaction, workspace: @workspace, account: @account, direction: "debit",
          amount_cents: amount_cents, occurred_at: on)
  end

  test "confident infere mensal com valor e próximo vencimento" do
    txs = [
      tx(amount_cents: 5990, on: Date.new(2026, 1, 10)),
      tx(amount_cents: 5990, on: Date.new(2026, 2, 10)),
      tx(amount_cents: 5990, on: Date.new(2026, 3, 10))
    ]
    g = Recurrences::Guess.confident(txs)
    assert_equal "monthly", g[:cadence]
    assert_equal 5990, g[:expected_amount_cents]
    assert_equal Date.new(2026, 4, 10), g[:next_expected_at]
  end

  test "confident retorna nil com menos de 3 ocorrências" do
    assert_nil Recurrences::Guess.confident([ tx(amount_cents: 100, on: Date.new(2026, 1, 1)) ])
  end

  test "confident retorna nil com cadência inconsistente" do
    txs = [
      tx(amount_cents: 100, on: Date.new(2026, 1, 3)),
      tx(amount_cents: 100, on: Date.new(2026, 1, 9)),
      tx(amount_cents: 100, on: Date.new(2026, 2, 20))
    ]
    assert_nil Recurrences::Guess.confident(txs)
  end

  test "seed usa o palpite confiável quando existe" do
    txs = [
      tx(amount_cents: 5990, on: Date.new(2026, 1, 10)),
      tx(amount_cents: 5990, on: Date.new(2026, 2, 10)),
      tx(amount_cents: 5990, on: Date.new(2026, 3, 10))
    ]
    assert_equal "monthly", Recurrences::Guess.seed(txs)[:cadence]
    assert_equal Date.new(2026, 4, 10), Recurrences::Guess.seed(txs)[:next_expected_at]
  end

  test "seed cai em mensal a partir do gasto mais recente quando não dá pra inferir" do
    txs = [ tx(amount_cents: 12000, on: Date.new(2026, 5, 6)) ]
    g = Recurrences::Guess.seed(txs)
    assert_equal "monthly", g[:cadence]
    assert_equal 12000, g[:expected_amount_cents]
    assert_equal Date.new(2026, 6, 6), g[:next_expected_at]
  end
end
