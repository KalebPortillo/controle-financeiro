class Api::V1::RecurrencesController < ApplicationController
  before_action :require_authentication!
  before_action :set_recurrence, only: [ :update, :destroy, :missed ]

  # GET /api/v1/recurrences — recorrentes do workspace (detectadas + manuais).
  def index
    recurrences = current_workspace.recurrences.order(:descriptor_pattern)
    render json: { recurrences: recurrences.map { |r| serialize(r) } }
  end

  # GET /api/v1/recurrences/upcoming?days=15 — vencimentos previstos para os
  # próximos N dias (RF9.3). Só ativas, ordenadas pelo vencimento mais próximo.
  def upcoming
    days  = params.fetch(:days, 15).to_i.clamp(1, 365)
    today = Date.current
    recurrences = current_workspace.recurrences
                                   .where(status: "active")
                                   .where(next_expected_at: today..(today + days))
                                   .order(:next_expected_at)
    render json: {
      recurrences: recurrences.map { |r| serialize(r).merge(days_until: (r.next_expected_at - today).to_i) }
    }
  end

  # GET /api/v1/recurrences/:id/missed — a recorrente esperada não chegou? (RF9.6)
  def missed
    render json: {
      missed:           @recurrence.missed?,
      next_expected_at: @recurrence.next_expected_at&.iso8601,
      days_overdue:     @recurrence.days_overdue,
      last_seen_at:     @recurrence.last_seen_at&.iso8601
    }
  end

  # POST /api/v1/recurrences — cadastro manual (RF9.2). `source` é sempre
  # "manual" aqui; recorrentes detectadas nascem no job de detecção (RF9.1).
  def create
    recurrence = current_workspace.recurrences.new(recurrence_params)
    # account_id fora do permit (Brakeman: FK em mass-assignment). Atribuído à
    # mão; a validação account_belongs_to_workspace barra account alheia (422).
    recurrence.account_id = params[:account_id]
    recurrence.source = "manual"
    recurrence.save!
    render json: { recurrence: serialize(recurrence) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_validation_error(e.record)
  end

  # PATCH /api/v1/recurrences/:id — editar tolerância, cadência, valor esperado,
  # próximo vencimento, ou mudar status (pausar/cancelar/reativar) — RF9.
  def update
    @recurrence.update!(update_params)
    render json: { recurrence: serialize(@recurrence) }
  rescue ActiveRecord::RecordInvalid => e
    render_validation_error(e.record)
  end

  # DELETE /api/v1/recurrences/:id
  def destroy
    @recurrence.destroy!
    head :no_content
  end

  private

  def set_recurrence
    @recurrence = current_workspace.recurrences.find(params[:id])
  end

  def recurrence_params
    params.permit(:descriptor_pattern, :expected_amount_cents,
                  :amount_tolerance_pct, :cadence, :next_expected_at)
  end

  # No update permitimos também status (pausar/cancelar). account_id não muda.
  def update_params
    params.permit(:descriptor_pattern, :expected_amount_cents,
                  :amount_tolerance_pct, :cadence, :next_expected_at, :status)
  end

  def serialize(rec)
    {
      id:                    rec.id,
      account_id:            rec.account_id,
      descriptor_pattern:    rec.descriptor_pattern,
      expected_amount_cents: rec.expected_amount_cents,
      amount_tolerance_pct:  rec.amount_tolerance_pct.to_f,
      cadence:               rec.cadence,
      next_expected_at:      rec.next_expected_at&.iso8601,
      status:                rec.status,
      source:                rec.source
    }
  end
end
