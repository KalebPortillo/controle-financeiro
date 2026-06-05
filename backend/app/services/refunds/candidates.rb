module Refunds
  # RF10.1 — dada uma transação de crédito (possível estorno), lista os gastos
  # (débitos) do workspace que mais provavelmente foram estornados. Heurística
  # simples, sem IA: valor compatível + recência, ainda não estornados. Ordena
  # por confiança (valor exato primeiro, depois mais recentes). Até MAX.
  class Candidates
    MAX        = 10
    WINDOW     = 90 # dias pra trás a partir da data do crédito
    AMOUNT_TOL = 0.10 # 10% de tolerância no valor (estorno parcial/total)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(credit:)
      @credit    = credit
      @workspace = credit.workspace
    end

    def call
      return [] unless @credit.direction == "credit"

      candidates
        .reject { |d| d.refunded_amount_cents >= d.amount_cents } # já totalmente estornado
        .sort_by { |d| [ amount_distance(d), -d.occurred_at.to_time.to_i ] }
        .first(MAX)
    end

    private

    def candidates
      lo = (@credit.amount_cents * (1 - AMOUNT_TOL)).floor
      hi = (@credit.amount_cents * (1 + AMOUNT_TOL)).ceil
      @workspace.transactions
                .where(direction: "debit", status: %w[pending consolidated])
                .where(amount_cents: lo..hi)
                .where(occurred_at: (@credit.occurred_at - WINDOW)..@credit.occurred_at)
    end

    def amount_distance(debit)
      (debit.amount_cents - @credit.amount_cents).abs
    end
  end
end
