module Api
  module V1
    class ReportsController < ApplicationController
      include TransactionSerialization

      before_action :require_authentication!

      # GET /api/v1/reports/overview?period=current_month | ?from=&to= (+ filtros)
      # Os KPIs de gasto/receita são sempre separados — a direção não se aplica ao
      # overview (ele mostra os dois). Conta/cartão/pessoa recortam ambos.
      def overview
        from, to = report_period
        prev_from, prev_to = previous_period(from, to)

        expense_cents  = debit_sum(from, to)
        income_cents   = credit_sum(from, to)
        prev_expense   = debit_sum(prev_from, prev_to)
        prev_income    = credit_sum(prev_from, prev_to)

        render json: {
          period: { from: from.iso8601, to: to.iso8601 },
          expense_cents: expense_cents,
          income_cents: income_cents,
          balance_cents: income_cents - expense_cents,
          top_tags: top_tags(from, to, limit: 6),
          top_categories: top_categories(from, to, limit: 5),
          previous_period_comparison: {
            expense_delta_pct: delta_pct(expense_cents, prev_expense),
            income_delta_pct:  delta_pct(income_cents,  prev_income)
          }
        }
      end

      # GET /api/v1/reports/by_tag?from=&to= (+ filtros, direction)
      def by_tag
        from, to = report_period

        rows = consolidated_scope(from, to)
          .joins(:tags)
          .group("tags.id, tags.name, tags.color")
          .select("tags.id, tags.name, tags.color, SUM(transactions.amount_cents) AS amount_cents, COUNT(transactions.id) AS transactions_count")
          .order("amount_cents DESC")

        render json: {
          tags: rows.map do |r|
            { tag_id: r.id, name: r.name, color: r.color,
              amount_cents: r.amount_cents.to_i,
              transactions_count: r.transactions_count.to_i }
          end
        }
      end

      # GET /api/v1/reports/by_category?from=&to= (+ filtros, direction)
      def by_category
        from, to = report_period

        txs = consolidated_scope(from, to)

        # Sum per category (may double-count shared transactions)
        category_rows = txs
          .joins(tags: :categories)
          .where("categories.workspace_id = ?", current_workspace.id)
          .group("categories.id, categories.name, categories.color")
          .select(
            "categories.id, categories.name, categories.color, " \
            "SUM(transactions.amount_cents) AS amount_cents, " \
            "COUNT(DISTINCT transactions.id) AS transactions_count"
          )
          .order("amount_cents DESC")

        # Overlap: transactions that belong to 2+ categories
        overlap_tx_ids = txs
          .joins(tags: :categories)
          .where("categories.workspace_id = ?", current_workspace.id)
          .group("transactions.id")
          .having("COUNT(DISTINCT categories.id) > 1")
          .pluck("transactions.id")

        # per-category: how many of its transactions are shared
        shared_by_category = if overlap_tx_ids.any?
          txs
            .joins(tags: :categories)
            .where("categories.workspace_id = ? AND transactions.id IN (?)", current_workspace.id, overlap_tx_ids)
            .group("categories.id")
            .count("DISTINCT transactions.id")
        else
          {}
        end

        total_distinct   = txs.sum(:amount_cents)
        sum_of_cats      = category_rows.sum { |r| r.amount_cents.to_i }
        overlap_present  = overlap_tx_ids.any?

        render json: {
          categories: category_rows.map do |r|
            { category_id: r.id, name: r.name, color: r.color,
              amount_cents: r.amount_cents.to_i,
              transactions_count: r.transactions_count.to_i,
              shared_with_other_categories_count: (shared_by_category[r.id] || 0).to_i }
          end,
          total_distinct_transactions_amount_cents: total_distinct,
          sum_of_categories_amount_cents: sum_of_cats,
          overlap_present: overlap_present
        }
      end

      # GET /api/v1/reports/monthly_evolution?months=12 (+ filtros)
      def monthly_evolution
        n_months = (params[:months] || 12).to_i.clamp(1, 24)
        from = (Date.current - (n_months - 1).months).beginning_of_month
        to   = Date.current.end_of_month

        rows = apply_report_filters(
          current_workspace.transactions.not_internal_transfer
            .where(status: "consolidated", occurred_at: from..to)
        )
          .group("DATE_TRUNC('month', occurred_at)")
          .select(
            "DATE_TRUNC('month', occurred_at) AS month, " \
            "SUM(CASE WHEN direction='debit'  THEN amount_cents ELSE 0 END) AS expense_cents, " \
            "SUM(CASE WHEN direction='credit' THEN amount_cents ELSE 0 END) AS income_cents"
          )
          .order("month")

        render json: {
          months: rows.map do |r|
            { period: r.month.strftime("%Y-%m"),
              expense_cents: r.expense_cents.to_i,
              income_cents:  r.income_cents.to_i }
          end
        }
      end

      # GET /api/v1/reports/category/:id?from=&to= (+ filtros, direction) — RF13.8
      # Detalhe de uma categoria no período: resumo (total, nº, participação %,
      # comparativo com o período anterior), quebra pelas tags-membro e a lista de
      # transações (serialização idêntica ao consolidado).
      def category_detail
        category = current_workspace.categories.find(params[:id])
        from, to = report_period
        tag_ids = category.tag_ids

        tx_ids = category_transaction_ids(consolidated_scope(from, to), tag_ids)
        transactions = load_transactions(tx_ids)
        amount = transactions.sum(&:amount_cents)

        prev_from, prev_to = previous_period(from, to)
        prev_ids = category_transaction_ids(consolidated_scope(prev_from, prev_to), tag_ids)
        prev_amount = current_workspace.transactions.where(id: prev_ids).sum(:amount_cents)

        breakdown = current_workspace.transactions.where(id: tx_ids)
          .joins(:tags).where(tags: { id: tag_ids })
          .group("tags.id, tags.name, tags.color")
          .select("tags.id, tags.name, tags.color, SUM(transactions.amount_cents) AS amount_cents, COUNT(transactions.id) AS transactions_count")
          .order("amount_cents DESC")
          .map { |r| breakdown_item(r.id, r.name, r.color, r.amount_cents, r.transactions_count) }

        render json: detail_payload(
          id: category.id, name: category.name, color: category.color,
          amount: amount, count: tx_ids.size, from: from, to: to,
          prev_amount: prev_amount, breakdown: breakdown, transactions: transactions
        )
      end

      # GET /api/v1/reports/tag/:id?from=&to= (+ filtros, direction) — RF13.8
      # Detalhe de uma tag no período: resumo + quebra por conta (onde foi gasto) +
      # lista de transações.
      def tag_detail
        tag = current_workspace.tags.find(params[:id])
        from, to = report_period

        in_tag = consolidated_scope(from, to).joins(:tags).where(tags: { id: tag.id })
        tx_ids = in_tag.distinct.pluck(:id)
        transactions = load_transactions(tx_ids)
        amount = transactions.sum(&:amount_cents)

        prev_from, prev_to = previous_period(from, to)
        prev_amount = consolidated_scope(prev_from, prev_to)
          .joins(:tags).where(tags: { id: tag.id }).sum(:amount_cents)

        breakdown = current_workspace.transactions.where(id: tx_ids)
          .joins(:account)
          .group("accounts.id, accounts.name")
          .select("accounts.id, accounts.name, SUM(transactions.amount_cents) AS amount_cents, COUNT(transactions.id) AS transactions_count")
          .order("amount_cents DESC")
          .map { |r| breakdown_item(r.id, r.name, nil, r.amount_cents, r.transactions_count) }

        render json: detail_payload(
          id: tag.id, name: tag.name, color: tag.color,
          amount: amount, count: tx_ids.size, from: from, to: to,
          prev_amount: prev_amount, breakdown: breakdown, transactions: transactions
        )
      end

      private

      # Período canônico: from/to (ISO) têm prioridade; senão cai no `period=`
      # (current_month/last_month/YYYY-MM).
      def report_period
        if params[:from].present? && params[:to].present?
          [ Date.parse(params[:from]), Date.parse(params[:to]) ]
        else
          resolve_period(params[:period])
        end
      rescue ArgumentError
        resolve_period(nil)
      end

      # Janela anterior de comparação: mês calendário completo → mês anterior;
      # range custom → janela imediatamente anterior de mesma duração.
      def previous_period(from, to)
        if from == from.beginning_of_month && to == from.end_of_month
          m = from.prev_month
          [ m.beginning_of_month, m.end_of_month ]
        else
          span = (to - from).to_i
          prev_to = from - 1
          [ prev_to - span, prev_to ]
        end
      end

      def resolve_period(period_param)
        case period_param
        when "current_month", nil
          [ Date.current.beginning_of_month, Date.current.end_of_month ]
        when "last_month"
          m = Date.current.prev_month
          [ m.beginning_of_month, m.end_of_month ]
        else
          # "YYYY-MM" format
          if period_param =~ /\A\d{4}-\d{2}\z/
            d = Date.parse("#{period_param}-01")
            [ d.beginning_of_month, d.end_of_month ]
          else
            [ Date.current.beginning_of_month, Date.current.end_of_month ]
          end
        end
      end

      # RF13.4 — filtros comuns a todos os endpoints (todos opcionais, combináveis):
      # conta(s), só cartão, e pessoa (dona da conta). Joins de `accounts`
      # deduplicados pelo AR quando mais de um filtro precisa deles.
      def apply_report_filters(relation)
        relation = relation.where(account_id: Array(params[:account_ids])) if params[:account_ids].present?
        if truthy?(params[:card_only]) || params[:membership_id].present?
          relation = relation.joins(:account)
          relation = relation.where(accounts: { kind: "credit_card" }) if truthy?(params[:card_only])
          relation = relation.where(accounts: { owner_membership_id: params[:membership_id] }) if params[:membership_id].present?
        end
        relation
      end

      # Direção analisada nos breakdowns/detalhe: débito (gasto) por padrão; o
      # filtro permite ver "receita por tag/categoria".
      def report_direction
        d = params[:direction].to_s
        %w[debit credit].include?(d) ? d : "debit"
      end

      # RF11 — exclui transferências internas. Base gasto-cêntrica (débito), usada
      # pela matemática de gasto do overview (independe do filtro de direção).
      def consolidated_debits(from, to)
        apply_report_filters(
          current_workspace.transactions.not_internal_transfer
            .where(status: "consolidated", direction: "debit", occurred_at: from..to)
        )
      end

      # Base dos breakdowns/detalhe: honra o filtro de direção (default débito).
      def consolidated_scope(from, to)
        apply_report_filters(
          current_workspace.transactions.not_internal_transfer
            .where(status: "consolidated", direction: report_direction, occurred_at: from..to)
        )
      end

      # RF10/RF11 — gasto efetivo: débitos (sem transferências) menos os estornos
      # recebidos por débitos do período (o estorno reduz o gasto, RF10.3).
      def debit_sum(from, to)
        consolidated_debits(from, to).sum(:amount_cents) - refunds_in_period(from, to)
      end

      # RF10/RF11 — receita real exclui créditos que são estornos (não é renda
      # nova) e os que são entrada de transferência interna.
      def credit_sum(from, to)
        apply_report_filters(
          current_workspace.transactions.not_internal_transfer
            .where(status: "consolidated", direction: "credit", occurred_at: from..to)
        ).where.missing(:refund_of).sum(:amount_cents)
      end

      # Soma dos estornos cujos GASTOS estornados caem no período (centavos).
      def refunds_in_period(from, to)
        TransactionRefund
          .where(refunded_transaction_id: consolidated_debits(from, to).select(:id))
          .joins(:refund_transaction)
          .sum("transactions.amount_cents")
      end

      def top_tags(from, to, limit: 6)
        consolidated_debits(from, to)
          .joins(:tags)
          .group("tags.id, tags.name, tags.color")
          .select("tags.id, tags.name, tags.color, SUM(transactions.amount_cents) AS amount_cents")
          .order("amount_cents DESC")
          .limit(limit)
          .map { |r| { tag_id: r.id, name: r.name, color: r.color, amount_cents: r.amount_cents.to_i } }
      end

      def top_categories(from, to, limit: 5)
        consolidated_debits(from, to)
          .joins(tags: :categories)
          .where("categories.workspace_id = ?", current_workspace.id)
          .group("categories.id, categories.name, categories.color")
          .select("categories.id, categories.name, categories.color, SUM(transactions.amount_cents) AS amount_cents")
          .order("amount_cents DESC")
          .limit(limit)
          .map { |r| { category_id: r.id, name: r.name, color: r.color, amount_cents: r.amount_cents.to_i } }
      end

      # Ids distintos das transações do escopo que têm alguma tag da categoria.
      def category_transaction_ids(scope, tag_ids)
        return [] if tag_ids.empty?
        scope.joins(:tags).where(tags: { id: tag_ids }).distinct.pluck(:id)
      end

      # Carrega + ordena + faz preload das transações para serialização.
      def load_transactions(ids)
        return [] if ids.empty?
        current_workspace.transactions.where(id: ids)
          .includes(*TransactionSerialization::SERIALIZE_INCLUDES)
          .order(occurred_at: :desc, created_at: :desc)
          .to_a
      end

      def breakdown_item(id, name, color, amount_cents, count)
        { id: id, name: name, color: color,
          amount_cents: amount_cents.to_i, transactions_count: count.to_i }
      end

      # Payload comum das telas de detalhe (categoria/tag).
      def detail_payload(id:, name:, color:, amount:, count:, from:, to:, prev_amount:, breakdown:, transactions:)
        {
          id: id, name: name, color: color,
          period: { from: from.iso8601, to: to.iso8601 },
          summary: {
            amount_cents: amount.to_i,
            transactions_count: count,
            share_pct: share_pct(amount, from, to),
            previous_amount_cents: prev_amount.to_i,
            delta_pct: delta_pct(amount, prev_amount)
          },
          breakdown: breakdown,
          transactions: transactions.map { |t| serialize(t) }
        }
      end

      # Participação % do valor no total do escopo (mesma direção) do período.
      def share_pct(amount, from, to)
        total = consolidated_scope(from, to).sum(:amount_cents)
        return 0.0 if total.zero?
        (amount.to_f / total * 100).round(1)
      end

      def delta_pct(current_val, previous_val)
        return nil if previous_val.nil? || previous_val.zero?
        ((current_val.to_f - previous_val) / previous_val * 100).round(1)
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
