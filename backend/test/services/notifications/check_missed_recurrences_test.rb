require "test_helper"

module Notifications
  class CheckMissedRecurrencesTest < ActiveSupport::TestCase
    def missed_recurrence(workspace: create(:workspace), days_late: 5)
      create(:recurrence, workspace: workspace,
                          next_expected_at: Date.current - days_late)
    end

    test "recorrência atrasada gera notificação recurrent_missed" do
      recurrence = missed_recurrence

      assert_difference -> { Notification.where(kind: "recurrent_missed").count }, 1 do
        CheckMissedRecurrences.call
      end

      n = recurrence.workspace.notifications.last
      assert_equal recurrence.id, n.payload["recurrence_id"]
      assert_equal recurrence.descriptor_pattern, n.payload["descriptor_pattern"]
      assert_equal 5, n.payload["days_overdue"]
      assert_equal 5990, n.payload["expected_amount_cents"]
      assert_equal recurrence.next_expected_at.iso8601, n.payload["expected_at"]
    end

    test "rodar duas vezes não duplica (dedup)" do
      missed_recurrence

      CheckMissedRecurrences.call
      assert_no_difference -> { Notification.count } do
        CheckMissedRecurrences.call
      end
    end

    test "next_expected_at avançou → nova ocorrência atrasada notifica de novo" do
      recurrence = missed_recurrence
      CheckMissedRecurrences.call

      recurrence.update!(next_expected_at: Date.current - 4)
      assert_difference -> { Notification.count }, 1 do
        CheckMissedRecurrences.call
      end
    end

    test "dentro do grace period não notifica" do
      missed_recurrence(days_late: Recurrence::GRACE_DAYS) # ainda dentro

      assert_no_difference -> { Notification.count } do
        CheckMissedRecurrences.call
      end
    end

    test "pausada não notifica" do
      r = missed_recurrence
      r.update!(status: "paused")

      assert_no_difference -> { Notification.count } do
        CheckMissedRecurrences.call
      end
    end

    test "sem next_expected_at não notifica" do
      create(:recurrence, next_expected_at: nil)

      assert_no_difference -> { Notification.count } do
        CheckMissedRecurrences.call
      end
    end

    test "transação consolidada casando o padrão desde o vencimento → não notifica" do
      recurrence = missed_recurrence
      # descriptor_pattern guarda a forma NORMALIZADA (sem dígitos) — o pattern
      # da factory ("NETFLIX 1") nunca casaria; usa um estável sob normalização.
      recurrence.update!(descriptor_pattern: "NETFLIX")
      create(:transaction, workspace: recurrence.workspace, account: recurrence.account,
                           status: "consolidated", direction: "debit",
                           original_description: "NETFLIX 4821",
                           occurred_at: Date.current - 1)

      assert_no_difference -> { Notification.count } do
        CheckMissedRecurrences.call
      end
    end
  end
end
