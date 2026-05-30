module Invoices
  # RF9.5 — fatura do cartão como objeto DERIVADO (sem entidade física).
  #
  # - status "open": agrega os débitos do mês de competência corrente.
  # - status "future": projeta os próximos meses a partir de (a) parcelas que
  #   ainda vão cair (parcelamentos em curso) e (b) recorrentes mensais ativas.
  #
  # Mês de competência = mês-calendário de occurred_at (RF14.2). Não modelamos
  # dia de fechamento do cartão — simplificação consciente desta fatia.
  class Builder
    FUTURE_MONTHS = 3

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(account:, status: "open", today: Date.current)
      @account = account
      @status  = status
      @today   = today
    end

    def call
      @status == "future" ? future_invoices : [ open_invoice ]
    end

    private

    # Débitos que entram na fatura: exclui estornos (credit), rejeitados e a
    # transação original de um split.
    def debits
      @debits ||= @account.transactions
                          .where(direction: "debit")
                          .where.not(status: %w[rejected split])
                          .to_a
    end

    def open_invoice
      month = @today.beginning_of_month
      txs = debits.select { |t| t.occurred_at.between?(month, month.end_of_month) }
      items = txs.map { |t| breakdown_item(t) if t.installment_group_id }.compact
      invoice(month, "open", total_cents: txs.sum(&:amount_cents),
                             transactions_count: txs.size, breakdown: items)
    end

    def future_invoices
      (1..FUTURE_MONTHS).map do |ahead|
        month = @today.beginning_of_month >> ahead
        items = projected_installments(month) + projected_recurrences
        invoice(month, "future",
                total_cents: items.sum { |i| i[:amount_cents] },
                transactions_count: items.size,
                breakdown: items.select { |i| i[:group_id] })
      end
    end

    # Parcelas que ainda vão cair: pega a última parcela vista de cada grupo e,
    # se ainda não chegou ao total, projeta a parcela correspondente ao mês.
    def projected_installments(month)
      installment_groups.filter_map do |_group_id, txs|
        latest = txs.max_by(&:installment_number)
        next if latest.installment_number >= latest.installment_total

        ahead  = months_between(latest.occurred_at.beginning_of_month, month)
        number = latest.installment_number + ahead
        next if ahead <= 0 || number > latest.installment_total

        breakdown_item(latest, number: number)
      end
    end

    # Recorrentes mensais ativas da conta entram uma vez por mês futuro.
    def projected_recurrences
      @account.recurrences
              .where(status: "active", cadence: "monthly")
              .where.not(expected_amount_cents: nil)
              .map { |r| { label: r.descriptor_pattern, amount_cents: r.expected_amount_cents } }
    end

    def installment_groups
      @installment_groups ||= debits.select(&:installment_group_id).group_by(&:installment_group_id)
    end

    def breakdown_item(tx, number: tx.installment_number)
      name = tx.improved_title.presence || tx.original_description
      {
        group_id:     tx.installment_group_id,
        label:        "#{name} #{number}/#{tx.installment_total}",
        amount_cents: tx.amount_cents
      }
    end

    def months_between(from_month, to_month)
      (to_month.year * 12 + to_month.month) - (from_month.year * 12 + from_month.month)
    end

    def invoice(month, status, total_cents:, transactions_count:, breakdown:)
      {
        account_id:             @account.id,
        period:                 { from: month.iso8601, to: month.end_of_month.iso8601 },
        status:                 status,
        total_cents:            total_cents,
        transactions_count:     transactions_count,
        installments_breakdown: breakdown
      }
    end
  end
end
