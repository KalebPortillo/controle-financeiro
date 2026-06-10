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
  end
end
