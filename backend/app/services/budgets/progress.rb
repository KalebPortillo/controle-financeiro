module Budgets
  # RF8.4 — progresso de um orçamento num período [from, to]: gasto consolidado
  # (RF8.6), % do teto, status (ok/warning/exceeded) e projeção pro fim do mês
  # pelo ritmo atual. Cada gasto conta UMA vez por orçamento mesmo que tenha
  # várias tags rastreadas (distinct) — RF6.6: não-duplicação DENTRO do orçamento.
  module Progress
    Result = Data.define(
      :budget, :spent_cents, :limit_cents, :pct, :status,
      :projection_cents, :remaining_cents
    )

    module_function

    def call(budget:, from:, to:, today: Date.current)
      spent = spent_cents(budget, from, to)
      limit = budget.monthly_limit_cents
      pct   = limit.positive? ? (spent * 100.0 / limit).round : 0

      Result.new(
        budget:           budget,
        spent_cents:      spent,
        limit_cents:      limit,
        pct:              pct,
        status:           status_for(pct, budget.alert_threshold_pct),
        projection_cents: projection(spent, from, to, today),
        remaining_cents:  limit - spent
      )
    end

    # Gasto do orçamento: soma dos débitos consolidados (sem transferências
    # internas) cujo id casa com QUALQUER tag rastreada — cada tx somada 1×.
    def spent_cents(budget, from, to)
      tag_ids = budget.tracked_tag_ids
      return 0 if tag_ids.empty?

      base = budget.workspace.transactions.not_internal_transfer
                   .where(status: "consolidated", direction: "debit", occurred_at: from..to)
      matching = base.joins(:transaction_tags)
                     .where(transaction_tags: { tag_id: tag_ids })
                     .select(:id).distinct
      budget.workspace.transactions.where(id: matching).sum(:amount_cents)
    end

    def status_for(pct, threshold)
      if pct >= 100 then "exceeded"
      elsif pct >= threshold then "warning"
      else "ok"
      end
    end

    # Projeção linear pelo ritmo até hoje (RF8.4). Fora do mês corrente (período
    # já fechado) a projeção é o próprio gasto; sem dias decorridos, idem.
    def projection(spent, from, to, today)
      return spent if today >= to # período encerrado
      return spent if today < from # período futuro: nada decorrido ainda

      total_days   = (to - from).to_i + 1
      elapsed_days = (today - from).to_i + 1
      return spent if elapsed_days <= 0

      (spent * total_days.to_f / elapsed_days).round
    end
  end
end
