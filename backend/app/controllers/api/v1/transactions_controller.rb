class Api::V1::TransactionsController < ApplicationController
  before_action :require_authentication!
  before_action :set_transaction, only: [ :update, :destroy, :consolidate, :reject, :edits ]

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

  # POST /api/v1/transactions — entrada manual (RF12). Vai direto pra
  # consolidados, na conta "Dinheiro / Externo" do workspace.
  def create
    transaction = current_workspace.transactions.new(
      account:               manual_account,
      direction:             params.require(:direction),
      amount_cents:          params.require(:amount_cents),
      occurred_at:           Date.parse(params.require(:occurred_at)),
      improved_title:        params[:improved_title].presence,
      original_description:  params[:improved_title].presence || "Lançamento manual",
      status:                "consolidated",
      source:                "manual_entry",
      consolidated_at:       Time.current,
      created_by_membership: current_membership
    )
    transaction.save!
    apply_tags(transaction, params[:tag_ids]) if params.key?(:tag_ids)
    render json: { transaction: serialize(transaction) }, status: :created
  rescue ActionController::ParameterMissing, ArgumentError => e
    render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_entity
  end

  # PATCH /api/v1/transactions/:id — edita título/valor/data (RF2.3) com optimistic
  # lock: o cliente manda o lock_version que tinha; conflito → 409.
  def update
    @transaction.lock_version = params[:lock_version] if params.key?(:lock_version)
    before_tags = @transaction.tags.pluck(:id).sort
    @transaction.assign_attributes(update_params)
    scalar_changes = @transaction.changes.slice("improved_title", "amount_cents", "occurred_at")
    apply_tags(@transaction, params[:tag_ids]) if params.key?(:tag_ids)
    @transaction.save!
    record_edits!(scalar_changes, before_tags)
    enqueue_learning_if_needed!(scalar_changes, before_tags)
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

  # GET /api/v1/transactions/:id/edits — trilha de alterações (RF4.3).
  def edits
    render json: { edits: @transaction.edits.recent.map { |e| serialize_edit(e) } }
  end

  # POST /api/v1/transactions/reanalyze — RF3.5 botão "Reanalisar com IA".
  def reanalyze
    pending_count = current_workspace.transactions.where(status: "pending").count
    AiSuggestion::ReanalyzeJob.perform_later(current_workspace.id)
    render json: { enqueued: true, pending_count: pending_count }, status: :accepted
  end

  private

  def set_transaction
    @transaction = current_workspace.transactions.find(params[:id])
  end

  # Registra um TransactionEdit por campo alterado (RF4.3). `scalar_changes` é o
  # dirty-tracking dos campos escalares; tags são comparadas por id (associação).
  def record_edits!(scalar_changes, before_tags)
    membership = current_membership
    return unless membership

    scalar_changes.each do |field, (old_v, new_v)|
      @transaction.edits.create!(
        edited_by_membership: membership, field_name: field, old_value: old_v, new_value: new_v
      )
    end

    return unless params.key?(:tag_ids)

    after_tags = @transaction.tags.reload.pluck(:id).sort
    return if after_tags == before_tags

    @transaction.edits.create!(
      edited_by_membership: membership, field_name: "tags",
      old_value: before_tags, new_value: after_tags
    )
  end

  def confidence_label(value)
    return nil if value.nil?
    if value >= 0.8 then "high"
    elsif value >= 0.5 then "medium"
    else "low"
    end
  end

  def enqueue_learning_if_needed!(scalar_changes, before_tags)
    title_changed = scalar_changes.key?("improved_title")
    tags_changed  = params.key?(:tag_ids) &&
                    @transaction.tags.pluck(:id).sort != before_tags
    return unless title_changed || tags_changed

    AiSuggestion::RecordCorrectionJob.perform_later(@transaction.id)
  end

  def update_params
    params.permit(:improved_title, :amount_cents, :occurred_at)
  end

  # Substitui as tags da transação (RF5.2). Escopado no workspace: ids de outro
  # workspace são silenciosamente ignorados.
  def apply_tags(transaction, tag_ids)
    ids = Array(tag_ids).map(&:to_s)
    transaction.tags = current_workspace.tags.where(id: ids)
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

  # Conta "Dinheiro / Externo" do workspace (RF12) — origem dos lançamentos
  # manuais (dinheiro vivo, PicPay, etc). Criada sob demanda, uma por workspace.
  def manual_account
    current_workspace.accounts.find_or_create_by!(institution: "manual", name: "Dinheiro / Externo") do |a|
      a.kind = "checking"
      a.owner_membership = current_membership
    end
  end

  def serialize_edit(e)
    {
      id:         e.id,
      field_name: e.field_name,
      old_value:  e.old_value,
      new_value:  e.new_value,
      edited_at:  e.created_at.iso8601,
      edited_by:  { id: e.edited_by_membership_id, name: e.edited_by_membership.user.name }
    }
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
      ai_confidence:        confidence_label(t.ai_confidence),
      ai_suggestion:        t.ai_suggestion,
      status:               t.status,
      source:               t.source,
      lock_version:         t.lock_version,
      tags:                 t.tags.order(:name).map { |tag| { id: tag.id, name: tag.name, color: tag.color, icon: tag.icon } }
    }
  end
end
