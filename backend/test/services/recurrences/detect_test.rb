require "test_helper"

# RF9.1 — detecção automática de recorrentes a partir do histórico consolidado:
# mesmo estabelecimento (descriptor normalizado) + valor próximo + cadência
# consistente → cria uma Recurrence com source "detected".
class Recurrences::DetectTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
  end

  # Cria uma transação consolidada (debit) com descrição/valor/data dados.
  def consolidated(description:, amount_cents:, on:, account: @account, direction: "debit")
    create(:transaction,
           workspace: @workspace, account: account,
           direction: direction, amount_cents: amount_cents,
           original_description: description, occurred_at: on,
           status: "consolidated", consolidated_at: Time.current)
  end

  test "detecta assinatura mensal e cria recorrente detected" do
    consolidated(description: "NETFLIX.COM 4821", amount_cents: 5990, on: Date.new(2026, 1, 10))
    consolidated(description: "NETFLIX.COM 5530", amount_cents: 5990, on: Date.new(2026, 2, 10))
    consolidated(description: "NETFLIX.COM 9912", amount_cents: 5990, on: Date.new(2026, 3, 10))

    assert_difference -> { @workspace.recurrences.count }, 1 do
      Recurrences::Detect.call(workspace: @workspace)
    end

    rec = @workspace.recurrences.sole
    assert_equal "detected", rec.source
    assert_equal "active",   rec.status
    assert_equal "monthly",  rec.cadence
    assert_equal @account.id, rec.account_id
    assert_equal 5990, rec.expected_amount_cents
    assert_equal "NETFLIX COM", rec.descriptor_pattern
    assert_equal Date.new(2026, 4, 10), rec.next_expected_at
  end

  test "detecta cadência semanal" do
    consolidated(description: "PADARIA", amount_cents: 1500, on: Date.new(2026, 3, 2))
    consolidated(description: "PADARIA", amount_cents: 1500, on: Date.new(2026, 3, 9))
    consolidated(description: "PADARIA", amount_cents: 1500, on: Date.new(2026, 3, 16))

    Recurrences::Detect.call(workspace: @workspace)
    assert_equal "weekly", @workspace.recurrences.sole.cadence
    assert_equal Date.new(2026, 3, 23), @workspace.recurrences.sole.next_expected_at
  end

  test "ignora transações pending (só consolidadas contam)" do
    3.times do |i|
      create(:transaction, workspace: @workspace, account: @account,
             original_description: "SPOTIFY", amount_cents: 1990,
             occurred_at: Date.new(2026, 1, 5) + (i * 30), status: "pending")
    end
    assert_no_difference -> { @workspace.recurrences.count } do
      Recurrences::Detect.call(workspace: @workspace)
    end
  end

  test "ignora créditos (só débitos viram recorrente de gasto)" do
    3.times do |i|
      consolidated(description: "SALARIO", amount_cents: 800000,
                   on: Date.new(2026, 1, 5) + (i * 30), direction: "credit")
    end
    assert_no_difference -> { @workspace.recurrences.count } do
      Recurrences::Detect.call(workspace: @workspace)
    end
  end

  test "exige no mínimo 3 ocorrências" do
    consolidated(description: "ACADEMIA", amount_cents: 9900, on: Date.new(2026, 1, 8))
    consolidated(description: "ACADEMIA", amount_cents: 9900, on: Date.new(2026, 2, 8))
    assert_no_difference -> { @workspace.recurrences.count } do
      Recurrences::Detect.call(workspace: @workspace)
    end
  end

  test "ignora cadência inconsistente" do
    consolidated(description: "ALEATORIO", amount_cents: 3000, on: Date.new(2026, 1, 3))
    consolidated(description: "ALEATORIO", amount_cents: 3000, on: Date.new(2026, 1, 9))  # +6d
    consolidated(description: "ALEATORIO", amount_cents: 3000, on: Date.new(2026, 2, 20)) # +42d
    assert_no_difference -> { @workspace.recurrences.count } do
      Recurrences::Detect.call(workspace: @workspace)
    end
  end

  test "ignora quando valores variam demais (não é 'valor próximo')" do
    consolidated(description: "MERCADO", amount_cents: 5000,  on: Date.new(2026, 1, 10))
    consolidated(description: "MERCADO", amount_cents: 25000, on: Date.new(2026, 2, 10))
    consolidated(description: "MERCADO", amount_cents: 5000,  on: Date.new(2026, 3, 10))
    assert_no_difference -> { @workspace.recurrences.count } do
      Recurrences::Detect.call(workspace: @workspace)
    end
  end

  test "é idempotente — roda 2x sem duplicar, atualiza next_expected_at" do
    consolidated(description: "NETFLIX", amount_cents: 5990, on: Date.new(2026, 1, 10))
    consolidated(description: "NETFLIX", amount_cents: 5990, on: Date.new(2026, 2, 10))
    consolidated(description: "NETFLIX", amount_cents: 5990, on: Date.new(2026, 3, 10))

    Recurrences::Detect.call(workspace: @workspace)
    assert_equal 1, @workspace.recurrences.count

    # Nova ocorrência muda o next_expected_at, mas não cria recorrente nova.
    consolidated(description: "NETFLIX", amount_cents: 5990, on: Date.new(2026, 4, 10))
    assert_no_difference -> { @workspace.recurrences.count } do
      Recurrences::Detect.call(workspace: @workspace)
    end
    assert_equal Date.new(2026, 5, 10), @workspace.recurrences.sole.next_expected_at
  end

  test "não sobrescreve recorrente manual com mesmo padrão/conta" do
    manual = create(:recurrence, workspace: @workspace, account: @account,
                    descriptor_pattern: "NETFLIX", source: "manual",
                    expected_amount_cents: 1000, cadence: "yearly")
    consolidated(description: "NETFLIX", amount_cents: 5990, on: Date.new(2026, 1, 10))
    consolidated(description: "NETFLIX", amount_cents: 5990, on: Date.new(2026, 2, 10))
    consolidated(description: "NETFLIX", amount_cents: 5990, on: Date.new(2026, 3, 10))

    assert_no_difference -> { @workspace.recurrences.count } do
      Recurrences::Detect.call(workspace: @workspace)
    end
    manual.reload
    assert_equal "manual", manual.source
    assert_equal 1000, manual.expected_amount_cents
    assert_equal "yearly", manual.cadence
  end

  test "escopado por workspace" do
    other_ws = create(:workspace)
    other_ac = create(:account, workspace: other_ws)
    [ other_ws ].each do
      3.times do |i|
        create(:transaction, workspace: other_ws, account: other_ac,
               original_description: "NETFLIX", amount_cents: 5990,
               occurred_at: Date.new(2026, 1, 10) + (i * 30),
               status: "consolidated", consolidated_at: Time.current)
      end
    end
    Recurrences::Detect.call(workspace: @workspace)
    assert_equal 0, @workspace.recurrences.count
    assert_equal 0, other_ws.recurrences.count, "não deve tocar em outro workspace"
  end
end
