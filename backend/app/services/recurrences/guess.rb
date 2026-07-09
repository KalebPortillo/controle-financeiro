module Recurrences
  # Palpite de cadência, valor esperado e próximo vencimento a partir de um
  # conjunto de transações que casam um padrão. Compartilhado entre a detecção
  # automática (RF9.1) e a criação manual semeada de um gasto (RF9.7).
  module Guess
    MIN_OCCURRENCES   = 3
    AMOUNT_SPREAD_MAX = 0.15 # (max - min) / mediana — "valor próximo" (RF9.1)

    # Faixas de gap (em dias) por cadência + como projetar o próximo vencimento.
    CADENCES = [
      { name: "weekly",  range: 5..9,     advance: ->(d) { d + 7 } },
      { name: "monthly", range: 26..35,   advance: ->(d) { d + 1.month } },
      { name: "yearly",  range: 350..380, advance: ->(d) { d + 1.year } }
    ].freeze

    module_function

    # Palpite CONFIÁVEL (RF9.1): cadência consistente + valores próximos + no
    # mínimo 3 ocorrências. Retorna {cadence, expected_amount_cents,
    # next_expected_at} ou nil quando não dá pra inferir com segurança.
    def confident(txs)
      txs = txs.sort_by(&:occurred_at)
      return if txs.size < MIN_OCCURRENCES

      dates   = txs.map(&:occurred_at)
      cadence = classify(dates.each_cons(2).map { |a, b| (b - a).to_i })
      return unless cadence

      amounts = txs.map(&:amount_cents)
      return unless amounts_close?(amounts)

      {
        cadence:               cadence[:name],
        expected_amount_cents: median(amounts),
        next_expected_at:      cadence[:advance].call(dates.last)
      }
    end

    # Palpite pra SEMEAR recorrência manual (RF9.7): usa o confiável quando
    # existe, senão cai em mensal a partir do gasto mais recente.
    def seed(txs)
      confident(txs) || fallback(txs)
    end

    def fallback(txs)
      last = txs.max_by(&:occurred_at)
      {
        cadence:               "monthly",
        expected_amount_cents: last&.amount_cents,
        next_expected_at:      last && (last.occurred_at + 1.month)
      }
    end

    # Classifica a cadência pela mediana dos gaps e exige que TODOS caiam na
    # mesma faixa (consistência) — senão não é recorrente confiável.
    def classify(gaps)
      cad = CADENCES.find { |c| c[:range].include?(median(gaps)) }
      return unless cad
      return unless gaps.all? { |g| cad[:range].include?(g) }

      cad
    end

    def amounts_close?(amounts)
      m = median(amounts).to_f
      return false if m.zero?

      (amounts.max - amounts.min) / m <= AMOUNT_SPREAD_MAX
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
    end
  end
end
