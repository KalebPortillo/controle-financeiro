class Api::V1::TransactionsController < ApplicationController
  before_action :require_authentication!
  before_action :set_transaction, only: [ :update, :destroy, :consolidate, :reject ]

  # GET /api/v1/transactions — listagem por status (inbox = pending), com filtros.
  def index
    scope = current_workspace.transactions
    scope = scope.where(status: status_filter)
    scope = scope.where(direction: params[:direction]) if params[:direction].present?
    scope = scope.where(account_id: params[:account_id]) if params[:account_id].present?
    scope = scope.where("occurred_at >= ?", params[:from]) if params[:from].present?
    scope = scope.where("occurred_at <= ?", params[:to]) if params[:to].present?
    scope = apply_search(scope, params[:q])

    transactions = scope.order(occurred_at: :desc, created_at: :desc)

    render json: {
      transactions:  transactions.map { |t| serialize(t) },
      pending_count: current_workspace.transactions.inbox.count
    }
  end

  # PATCH /api/v1/transactions/:id — edita título/valor/data (RF2.3) com optimistic
  # lock: o cliente manda o lock_version que tinha; conflito → 409.
  def update
    @transaction.lock_version = params[:lock_version] if params.key?(:lock_version)
    @transaction.assign_attributes(update_params)
    @transaction.save!
    render json: { transaction: serialize(@transaction) }
  rescue ActiveRecord::StaleObjectError
    render json: { error: { code: "stale_object", message: "Transação alterada por outra pessoa. Recarregue." } },
           status: :conflict
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: { code: "validation_failed", message: e.message } },
           status: :unprocessable_entity
  end

  # DELETE /api/v1/transactions/:id — exclusão definitiva (RF2.3 remover).
  def destroy
    @transaction.destroy!
    head :no_content
  end

  # POST /api/v1/transactions/:id/consolidate — aceitar (RF2.3).
  def consolidate
    @transaction.update!(status: "consolidated", consolidated_at: Time.current)
    render json: { transaction: serialize(@transaction) }
  end

  # POST /api/v1/transactions/:id/reject — rejeitar (RF2.3).
  def reject
    @transaction.update!(status: "rejected", rejected_at: Time.current)
    render json: { transaction: serialize(@transaction) }
  end

  private

  def set_transaction
    @transaction = current_workspace.transactions.find(params[:id])
  end

  def update_params
    params.permit(:improved_title, :amount_cents, :occurred_at)
  end

  # Default da inbox é pending; aceita override por status válido.
  def status_filter
    status = params[:status].presence
    Transaction::STATUSES.include?(status) ? status : "pending"
  end

  def apply_search(scope, query)
    return scope if query.blank?

    like = "%#{query.strip.downcase}%"
    scope.where(
      "LOWER(original_description) LIKE :q OR LOWER(COALESCE(improved_title, '')) LIKE :q",
      q: like
    )
  end

  # Workspace ativo da sessão (ou o primeiro). Espelha BankConnectionsController;
  # extrair pra concern quando um terceiro controller precisar.
  def current_workspace
    selected   = session[:active_workspace_id]
    workspaces = current_user.workspaces
    (selected && workspaces.find_by(id: selected)) || workspaces.order(:created_at).first
  end

  def serialize(t)
    {
      id:                   t.id,
      account_id:           t.account_id,
      account_name:         t.account&.name,
      direction:            t.direction,
      amount_cents:         t.amount_cents,
      currency:             t.currency,
      occurred_at:          t.occurred_at.iso8601,
      original_description: t.original_description,
      improved_title:       t.improved_title,
      status:               t.status,
      source:               t.source,
      lock_version:         t.lock_version
    }
  end
end
