class Api::V1::RecurrencesController < ApplicationController
  before_action :require_authentication!
  before_action :set_recurrence, only: [ :update, :destroy ]

  # GET /api/v1/recurrences — recorrentes do workspace (detectadas + manuais).
  def index
    recurrences = current_workspace.recurrences.order(:descriptor_pattern)
    render json: { recurrences: recurrences.map { |r| serialize(r) } }
  end

  # POST /api/v1/recurrences — cadastro manual (RF9.2). `source` é sempre
  # "manual" aqui; recorrentes detectadas nascem no job de detecção (RF9.1).
  def create
    recurrence = current_workspace.recurrences.new(recurrence_params)
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
    params.permit(:account_id, :descriptor_pattern, :expected_amount_cents,
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
