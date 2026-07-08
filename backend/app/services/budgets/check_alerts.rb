module Budgets
  # RF8.5 — dispara notificação quando um orçamento cruza o alerta (threshold, ex.
  # 80%) ou o teto (100%) no mês corrente. Chamado após consolidar gasto(s). O
  # `dedup_key` (único por workspace) garante NO MÁXIMO uma notificação de cada
  # nível por orçamento por mês — cruzar de novo no mesmo mês é no-op idempotente.
  module CheckAlerts
    module_function

    def call(workspace:, today: Date.current)
      from      = today.beginning_of_month
      to        = today.end_of_month
      month_key = today.strftime("%Y-%m")

      workspace.budgets.active_on(today)
               .includes(:target_tag, :target_category, :composite_tags)
               .find_each do |budget|
        progress = Budgets::Progress.call(budget: budget, from: from, to: to, today: today)
        kind = alert_kind(progress.status)
        notify(budget, progress, kind, month_key) if kind
      end
    end

    def alert_kind(status)
      case status
      when "exceeded" then "budget_exceeded"
      when "warning"  then "budget_warning"
      end
    end

    def notify(budget, progress, kind, month_key)
      Notifications::Create.call(
        workspace: budget.workspace,
        kind:      kind,
        dedup_key: "#{kind}:#{budget.id}:#{month_key}",
        payload: {
          budget_id:   budget.id,
          budget_name: budget.name,
          spent_cents: progress.spent_cents,
          limit_cents: progress.limit_cents,
          pct:         progress.pct
        }
      )
    end
  end
end
