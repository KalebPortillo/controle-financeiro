module Recurrences
  # RF9.1 — detecção automática de recorrentes a partir do histórico
  # consolidado. Agrupa débitos consolidados por (conta, descritor normalizado)
  # e, quando há cadência consistente + valores próximos, cria/atualiza uma
  # Recurrence com source "detected".
  #
  # Não responsável por avisar atrasos (RF9.6) nem projetar vencimentos
  # (RF9.3) — isso fica em fatias seguintes. Aqui só popula/atualiza o catálogo.
  class Detect
    MIN_OCCURRENCES   = 3
    AMOUNT_SPREAD_MAX = 0.15 # (max - min) / mediana — "valor próximo" (RF9.1)

    # Faixas de gap (em dias) por cadência + como projetar o próximo vencimento.
    CADENCES = [
      { name: "weekly",  range: 5..9,     advance: ->(d) { d + 7 } },
      { name: "monthly", range: 26..35,   advance: ->(d) { d + 1.month } },
      { name: "yearly",  range: 350..380, advance: ->(d) { d + 1.year } }
    ].freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(workspace:)
      @workspace = workspace
    end

    # Retorna as recorrentes criadas/atualizadas nesta passagem.
    def call
      groups = @workspace.transactions
                         .consolidated
                         .where(direction: "debit")
                         .order(:occurred_at)
                         .group_by { |t| [ t.account_id, normalize(t.original_description) ] }

      groups.filter_map { |(account_id, pattern), txs| detect_group(account_id, pattern, txs) }
    end

    private

    def detect_group(account_id, pattern, txs)
      return if pattern.blank? || txs.size < MIN_OCCURRENCES

      dates = txs.map(&:occurred_at)
      gaps  = dates.each_cons(2).map { |a, b| (b - a).to_i }
      cadence = classify(gaps)
      return unless cadence

      amounts = txs.map(&:amount_cents)
      return unless amounts_close?(amounts)

      existing = @workspace.recurrences.find_by(account_id: account_id, descriptor_pattern: pattern)
      return if existing&.source == "manual" # nunca sobrescreve cadastro manual

      rec = existing || @workspace.recurrences.new(
        account_id: account_id, descriptor_pattern: pattern, source: "detected"
      )
      rec.assign_attributes(
        expected_amount_cents: median(amounts),
        cadence:               cadence[:name],
        next_expected_at:      cadence[:advance].call(dates.last),
        status:                rec.status.presence || "active"
      )
      rec.save!
      rec
    end

    # Classifica a cadência pela mediana dos gaps e exige que TODOS os gaps
    # caiam na mesma faixa (consistência) — senão não é recorrente confiável.
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

    # "NETFLIX.COM 4821" → "NETFLIX COM". Tira dígitos e pontuação, normaliza
    # caixa e espaços — agrupa o mesmo estabelecimento apesar do ruído da fatura.
    def normalize(desc)
      desc.to_s.upcase.gsub(/\d+/, " ").gsub(/[^[:alpha:] ]/, " ").squish
    end
  end
end
