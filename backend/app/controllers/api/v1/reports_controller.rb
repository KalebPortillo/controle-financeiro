module Api
  module V1
    class ReportsController < ApplicationController
      before_action :require_authentication!

      # GET /api/v1/reports/overview?period=current_month
      def overview
        from, to = resolve_period(params[:period])
        prev_from = from.prev_month.beginning_of_month
        prev_to   = from.prev_month.end_of_month

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

      # GET /api/v1/reports/by_tag?from=YYYY-MM-DD&to=YYYY-MM-DD
      def by_tag
        from = Date.parse(params[:from])
        to   = Date.parse(params[:to])

        rows = consolidated_debits(from, to)
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

      # GET /api/v1/reports/by_category?from=YYYY-MM-DD&to=YYYY-MM-DD
      def by_category
        from = Date.parse(params[:from])
        to   = Date.parse(params[:to])

        txs = consolidated_debits(from, to)

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

      # GET /api/v1/reports/monthly_evolution?months=12
      def monthly_evolution
        n_months = (params[:months] || 12).to_i.clamp(1, 24)
        from = (Date.current - (n_months - 1).months).beginning_of_month
        to   = Date.current.end_of_month

        rows = current_workspace.transactions
          .where(status: "consolidated", occurred_at: from..to)
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

      private

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

      def consolidated_debits(from, to)
        current_workspace.transactions
          .where(status: "consolidated", direction: "debit", occurred_at: from..to)
      end

      def debit_sum(from, to)
        current_workspace.transactions
          .where(status: "consolidated", direction: "debit", occurred_at: from..to)
          .sum(:amount_cents)
      end

      def credit_sum(from, to)
        current_workspace.transactions
          .where(status: "consolidated", direction: "credit", occurred_at: from..to)
          .sum(:amount_cents)
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

      def delta_pct(current_val, previous_val)
        return nil if previous_val.nil? || previous_val.zero?
        ((current_val.to_f - previous_val) / previous_val * 100).round(1)
      end
    end
  end
end
