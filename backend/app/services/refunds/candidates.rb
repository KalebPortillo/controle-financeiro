module Refunds
  # RF10.1 — candidatos a estorno, nos DOIS sentidos:
  #   - a partir de um CRÉDITO (possível estorno) → lista os gastos (débitos) que
  #     ele pode estar estornando;
  #   - a partir de um DÉBITO (gasto) → lista os créditos que podem tê-lo estornado.
  # Heurística simples, sem IA: valor compatível + recência, ainda disponíveis.
  # Ordena por confiança (valor exato primeiro, depois mais recentes). Até MAX.
  class Candidates
    MAX        = 10
    WINDOW     = 90 # dias de janela (débito olha pra trás; crédito olha pra frente)
    AMOUNT_TOL = 0.10 # 10% de tolerância no valor (estorno parcial/total)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    # `transaction:` é o canônico; `credit:` mantido por compatibilidade.
    def initialize(transaction: nil, credit: nil)
      @transaction = transaction || credit
      @workspace   = @transaction.workspace
    end

    def call
      case @transaction.direction
      when "credit" then debit_candidates
      when "debit"  then credit_candidates
      else []
      end
    end

    private

    # Crédito → gastos que ele pode estar estornando (débitos ainda não totalmente
    # estornados, na janela ANTERIOR ao crédito).
    def debit_candidates
      @workspace.transactions
                .where(direction: "debit", status: %w[pending consolidated])
                .where(amount_cents: amount_range)
                .where(occurred_at: (@transaction.occurred_at - WINDOW)..@transaction.occurred_at)
                .reject { |d| d.refunded_amount_cents >= d.amount_cents }
                .sort_by { |d| [ amount_distance(d), -d.occurred_at.to_time.to_i ] }
                .first(MAX)
    end

    # Gasto → créditos que podem tê-lo estornado (créditos que ainda NÃO estornam
    # nenhum gasto, na janela POSTERIOR ao gasto).
    def credit_candidates
      @workspace.transactions
                .where(direction: "credit", status: %w[pending consolidated])
                .where(amount_cents: amount_range)
                .where(occurred_at: @transaction.occurred_at..(@transaction.occurred_at + WINDOW))
                .where.not(id: TransactionRefund.select(:refund_transaction_id))
                .sort_by { |c| [ amount_distance(c), -c.occurred_at.to_time.to_i ] }
                .first(MAX)
    end

    def amount_range
      lo = (@transaction.amount_cents * (1 - AMOUNT_TOL)).floor
      hi = (@transaction.amount_cents * (1 + AMOUNT_TOL)).ceil
      lo..hi
    end

    def amount_distance(other)
      (other.amount_cents - @transaction.amount_cents).abs
    end
  end
end
