class Api::V1::RecurrencesController < ApplicationController
  before_action :require_authentication!
  before_action :set_recurrence, only: [ :update, :destroy, :missed, :transactions ]

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

  # GET /api/v1/recurrences/:id/transactions — os gastos (consolidados) desta
  # recorrência, mais recentes primeiro (RF9 — histórico), incluindo os
  # removidos do grupo (RF9.7) marcados com `excluded: true` pra o usuário
  # poder restaurar.
  def transactions
    included = @recurrence.occurrences.first(24).map { |t| serialize_tx(t, excluded: false) }
    excluded = @recurrence.excluded_occurrences.map { |t| serialize_tx(t, excluded: true) }
    render json: { transactions: included + excluded }
  end

  # POST /api/v1/recurrences — cadastro manual (RF9.2) ou, quando vem
  # `transaction_id`, marca aquele gasto como recorrente e semeia a recorrência
  # (descritor + palpite de cadência/valor) — RF9.7. `source` é sempre "manual".
  def create
    return create_from_transaction if params[:transaction_id].present?

    recurrence = current_workspace.recurrences.new(recurrence_params)
    # account_id fora do permit (Brakeman: FK em mass-assignment). Atribuído à
    # mão; a validação account_belongs_to_workspace barra account alheia (422).
    recurrence.account_id = params[:account_id]
    recurrence.source = "manual"
    recurrence.save!
    render json: { recurrence: serialize(recurrence) }, status: :created
  end

  # PATCH /api/v1/recurrences/:id — editar tolerância, cadência, valor esperado,
  # próximo vencimento, ou mudar status (pausar/cancelar/reativar) — RF9.
  def update
    @recurrence.update!(update_params)
    render json: { recurrence: serialize(@recurrence) }
  end

  # DELETE /api/v1/recurrences/:id
  def destroy
    @recurrence.destroy!
    head :no_content
  end

  private

  # RF9.7 — semeia uma recorrência manual a partir de um gasto. Idempotente:
  # se já existe recorrência pra (conta, descritor), devolve a existente (200).
  def create_from_transaction
    tx = current_workspace.transactions.find(params[:transaction_id])
    descriptor = Recurrences::Descriptor.normalize(tx.original_description)

    existing = current_workspace.recurrences.find_by(account_id: tx.account_id, descriptor_pattern: descriptor)
    return render json: { recurrence: serialize(existing) }, status: :ok if existing

    seed = tx.account.transactions.consolidated.where(direction: "debit").select do |t|
      Recurrences::Descriptor.normalize(t.original_description) == descriptor
    end
    guess = Recurrences::Guess.seed(seed.presence || [ tx ])

    recurrence = current_workspace.recurrences.new(
      account_id: tx.account_id, descriptor_pattern: descriptor, source: "manual", **guess
    )
    recurrence.save!
    render json: { recurrence: serialize(recurrence) }, status: :created
  end

  def serialize_tx(tx, excluded:)
    {
      id:           tx.id,
      title:        tx.improved_title.presence || tx.original_description,
      amount_cents: tx.amount_cents,
      occurred_at:  tx.occurred_at.iso8601,
      excluded:     excluded
    }
  end

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
