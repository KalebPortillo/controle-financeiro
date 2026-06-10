module Notifications
  # Varredura diária (RF9.6 + RF17): recorrência ativa, vencida além do grace
  # e sem transação casando desde o vencimento → notificação recurrent_missed.
  # Dedup por (recorrência, vencimento): a mesma pendência não re-notifica nos
  # dias seguintes; quando o next_expected_at avança (nova ocorrência), avisa
  # de novo.
  module CheckMissedRecurrences
    module_function

    def call(today: Date.current)
      Recurrence.where(status: "active").where.not(next_expected_at: nil)
                .includes(:workspace).find_each do |recurrence|
        next unless recurrence.missed?(today: today)

        Notifications::Create.call(
          workspace: recurrence.workspace,
          kind:      "recurrent_missed",
          dedup_key: "recurrent_missed:#{recurrence.id}:#{recurrence.next_expected_at}",
          payload:   {
            "recurrence_id"         => recurrence.id,
            "descriptor_pattern"    => recurrence.descriptor_pattern,
            "expected_at"           => recurrence.next_expected_at.iso8601,
            "days_overdue"          => recurrence.days_overdue(today: today),
            "expected_amount_cents" => recurrence.expected_amount_cents
          }
        )
      end
    end
  end
end
