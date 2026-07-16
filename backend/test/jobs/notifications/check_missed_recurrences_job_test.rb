require "test_helper"

module Notifications
  # Agendado diário (config/recurring.yml) — o contrato do JOB é só delegar pro
  # CheckMissedRecurrences (a lógica de atraso/dedup tem teste próprio no service).
  class CheckMissedRecurrencesJobTest < ActiveJob::TestCase
    test "gera notificação recurrent_missed pra recorrência atrasada" do
      create(:recurrence, next_expected_at: Date.current - 5)

      assert_difference -> { Notification.where(kind: "recurrent_missed").count }, 1 do
        CheckMissedRecurrencesJob.perform_now
      end
    end
  end
end
