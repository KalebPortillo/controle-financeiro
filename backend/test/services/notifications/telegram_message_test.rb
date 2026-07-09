require "test_helper"

module Notifications
  class TelegramMessageTest < ActiveSupport::TestCase
    test "sync_failed com instituição e motivo truncado" do
      n = build(:notification, kind: "sync_failed", payload: {
        "institution_label" => "Nubank",
        "error_message"     => "Credenciais expiradas" + ("x" * 200)
      })

      msg = TelegramMessage.call(n)
      assert_match(/\AFalha na sincronização do Nubank\. Motivo: Credenciais expiradas/, msg)
      assert_operator msg.length, :<=, 200
      assert_match(/Verifique a conexão no app\.\z/, msg)
    end

    test "sync_failed sem error_message" do
      n = build(:notification, kind: "sync_failed", payload: { "institution_label" => "Inter" })

      assert_equal "Falha na sincronização do Inter. Verifique a conexão no app.",
                   TelegramMessage.call(n)
    end

    test "inbox_new plural" do
      n = build(:notification, kind: "inbox_new", payload: { "count" => 7 })

      assert_equal "Sincronização concluída: 7 novos gastos aguardando revisão na inbox.",
                   TelegramMessage.call(n)
    end

    test "inbox_new singular" do
      n = build(:notification, kind: "inbox_new", payload: { "count" => 1 })

      assert_equal "Sincronização concluída: 1 novo gasto aguardando revisão na inbox.",
                   TelegramMessage.call(n)
    end

    test "recurrent_missed com valor" do
      n = build(:notification, kind: "recurrent_missed", payload: {
        "descriptor_pattern"    => "NETFLIX",
        "expected_at"           => "2026-06-05",
        "days_overdue"          => 5,
        "expected_amount_cents" => 5590
      })

      assert_equal "Recorrente atrasada: NETFLIX. Esperada em 05/06/2026, " \
                   "5 dias de atraso (valor previsto R$ 55,90).",
                   TelegramMessage.call(n)
    end

    test "recurrent_missed sem valor, 1 dia" do
      n = build(:notification, kind: "recurrent_missed", payload: {
        "descriptor_pattern" => "ALUGUEL",
        "expected_at"        => "2026-06-09",
        "days_overdue"       => 1
      })

      assert_equal "Recorrente atrasada: ALUGUEL. Esperada em 09/06/2026, 1 dia de atraso.",
                   TelegramMessage.call(n)
    end

    test "valor com milhar" do
      n = build(:notification, kind: "recurrent_missed", payload: {
        "descriptor_pattern"    => "ALUGUEL",
        "expected_at"           => "2026-06-01",
        "days_overdue"          => 9,
        "expected_amount_cents" => 123_456
      })

      assert_match(/R\$ 1\.234,56/, TelegramMessage.call(n))
    end

    test "budget_warning com nome e percentual" do
      n = build(:notification, kind: "budget_warning", payload: {
        "budget_name" => "Mercado", "pct" => 85, "spent_cents" => 85_000, "limit_cents" => 100_000
      })
      msg = TelegramMessage.call(n)
      assert_match(/Orçamento "Mercado" em 85% do teto/, msg)
      assert_match(/R\$ 850,00 de R\$ 1\.000,00/, msg)
    end

    test "budget_exceeded" do
      n = build(:notification, kind: "budget_exceeded", payload: {
        "budget_name" => "Lazer", "pct" => 130, "spent_cents" => 130_000, "limit_cents" => 100_000
      })
      assert_match(/Orçamento "Lazer" estourou: R\$ 1\.300,00 de R\$ 1\.000,00 \(130%\)/, TelegramMessage.call(n))
    end

    test "refund_auto_linked com gasto e valor" do
      n = build(:notification, kind: "refund_auto_linked", payload: {
        "refunded_title" => "Compra Amazon", "amount_cents" => 8990
      })
      assert_equal "Estorno vinculado automaticamente a \"Compra Amazon\" (R$ 89,90). " \
                   "Desfaça no app se não for.",
                   TelegramMessage.call(n)
    end
  end
end
