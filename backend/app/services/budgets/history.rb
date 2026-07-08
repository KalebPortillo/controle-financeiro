module Budgets
  # RF8 (detalhe) — histórico do orçamento nos últimos N meses (inclui o corrente),
  # em ordem cronológica. Cada mês reusa Budgets::Progress; o teto comparado é o
  # atual do orçamento (não guardamos histórico de tetos). Projeção é ignorada aqui.
  module History
    DEFAULT_MONTHS = 6

    Entry = Data.define(:month, :spent_cents, :limit_cents, :pct, :status)

    module_function

    def call(budget:, months: DEFAULT_MONTHS, today: Date.current)
      (0...months).map { |i| entry_for(budget, today << i, today) }.reverse
    end

    def entry_for(budget, ref_date, today)
      from = ref_date.beginning_of_month
      to   = ref_date.end_of_month
      p    = Budgets::Progress.call(budget: budget, from: from, to: to, today: today)
      Entry.new(
        month:       from.strftime("%Y-%m"),
        spent_cents: p.spent_cents,
        limit_cents: p.limit_cents,
        pct:         p.pct,
        status:      p.status
      )
    end
  end
end
