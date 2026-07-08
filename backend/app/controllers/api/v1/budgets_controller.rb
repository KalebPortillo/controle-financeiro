class Api::V1::BudgetsController < ApplicationController
  before_action :require_authentication!
  before_action :set_budget, only: [ :show, :update, :destroy ]

  # GET /api/v1/budgets?period=current_month — lista os orçamentos com o progresso
  # calculado no período (RF8). Default: mês corrente.
  def index
    from, to = resolve_period(params[:period])
    budgets  = current_workspace.budgets
                                .includes(:target_tag, :target_category, :composite_tags)
                                .order(:name)
    overlap  = overlapping_budget_ids(budgets)

    render json: {
      period:  { from: from.iso8601, to: to.iso8601 },
      budgets: budgets.map { |b| serialize(b, from, to, overlap.include?(b.id)) }
    }
  end

  # GET /api/v1/budgets/:id — detalhe: progresso do mês, histórico multi-mês e as
  # transações consolidadas que compõem o gasto do mês corrente (RF8 detalhe).
  def show
    from, to = resolve_period(params[:period])
    render json: {
      budget:       serialize(@budget, from, to, false),
      history:      Budgets::History.call(budget: @budget).map { |e| history_entry(e) },
      transactions: composing_transactions(@budget, from, to)
    }
  end

  # POST /api/v1/budgets
  def create
    budget = current_workspace.budgets.new(budget_params)
    assign_composite_tags(budget)
    budget.save!
    from, to = resolve_period(params[:period])
    render json: { budget: serialize(budget, from, to, false) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_validation_message(e.message)
  end

  # PATCH /api/v1/budgets/:id
  def update
    @budget.assign_attributes(budget_params)
    assign_composite_tags(@budget)
    @budget.save!
    from, to = resolve_period(params[:period])
    render json: { budget: serialize(@budget, from, to, false) }
  rescue ActiveRecord::RecordInvalid => e
    render_validation_message(e.message)
  end

  # DELETE /api/v1/budgets/:id
  def destroy
    @budget.destroy!
    head :no_content
  end

  private

  def set_budget
    @budget = current_workspace.budgets.find(params[:id])
  end

  def budget_params
    params.permit(:name, :kind, :monthly_limit_cents, :alert_threshold_pct,
                  :starts_on, :ends_on, :enabled, :target_tag_id, :target_category_id)
  end

  # Composite: substitui as tags do orçamento pelas informadas (escopadas ao ws).
  def assign_composite_tags(budget)
    return unless budget.kind == "composite" && params.key?(:composite_tag_ids)

    ids = Array(params[:composite_tag_ids]).map(&:to_s)
    budget.composite_tags = current_workspace.tags.where(id: ids)
  end

  # Ids de orçamentos que compartilham ao menos uma tag rastreada com outro
  # orçamento habilitado (RF6.6/RF8.2 — sinalizar overlap). O(n²) sobre poucos.
  def overlapping_budget_ids(budgets)
    enabled = budgets.select(&:enabled)
    tag_sets = enabled.to_h { |b| [ b.id, b.tracked_tag_ids.to_set ] }
    enabled.each_with_object(Set.new) do |b, acc|
      mine = tag_sets[b.id]
      next if mine.empty?

      others = enabled.any? { |o| o.id != b.id && mine.intersect?(tag_sets[o.id]) }
      acc << b.id if others
    end
  end

  def history_entry(e)
    { month: e.month, spent_cents: e.spent_cents, limit_cents: e.limit_cents,
      pct: e.pct, status: e.status }
  end

  # Débitos consolidados (sem transferências) que compõem o gasto do orçamento no
  # período — cada transação uma vez, mais recentes primeiro.
  def composing_transactions(budget, from, to)
    tag_ids = budget.tracked_tag_ids
    return [] if tag_ids.empty?

    ids = current_workspace.transactions.not_internal_transfer
                           .where(status: "consolidated", direction: "debit", occurred_at: from..to)
                           .joins(:transaction_tags).where(transaction_tags: { tag_id: tag_ids })
                           .select(:id).distinct
    current_workspace.transactions.where(id: ids).order(occurred_at: :desc).map do |t|
      {
        id:           t.id,
        title:        t.improved_title.presence || t.original_description,
        amount_cents: t.amount_cents,
        occurred_at:  t.occurred_at.iso8601
      }
    end
  end

  def resolve_period(period)
    case period
    when "last_month"
      m = Date.current.prev_month
      [ m.beginning_of_month, m.end_of_month ]
    else
      [ Date.current.beginning_of_month, Date.current.end_of_month ]
    end
  end

  def serialize(budget, from, to, overlap)
    p = Budgets::Progress.call(budget: budget, from: from, to: to)
    {
      id:                  budget.id,
      name:                budget.name,
      kind:                budget.kind,
      monthly_limit_cents: budget.monthly_limit_cents,
      alert_threshold_pct: budget.alert_threshold_pct,
      enabled:             budget.enabled,
      starts_on:           budget.starts_on&.iso8601,
      ends_on:             budget.ends_on&.iso8601,
      target_tag:          budget.target_tag && { id: budget.target_tag.id, name: budget.target_tag.name, color: budget.target_tag.color },
      target_category:     budget.target_category && { id: budget.target_category.id, name: budget.target_category.name, color: budget.target_category.color },
      composite_tags:      budget.composite_tags.map { |t| { id: t.id, name: t.name, color: t.color } },
      overlap:             overlap,
      progress: {
        spent_cents:      p.spent_cents,
        limit_cents:      p.limit_cents,
        pct:              p.pct,
        status:           p.status,
        projection_cents: p.projection_cents,
        remaining_cents:  p.remaining_cents
      }
    }
  end
end
