class Api::V1::TransactionsController < ApplicationController
  before_action :require_authentication!
  before_action :set_transaction, only: [ :update, :destroy, :consolidate, :reject, :edits, :source,
                                          :refund_candidates, :link_refund ]

  # GET /api/v1/transactions — listagem por status (inbox = pending), com filtros.
  def index
    scope = current_workspace.transactions
    scope = scope.where(status: status_filter)
    scope = scope.where(direction: params[:direction]) if params[:direction].present?
    scope = scope.where(account_id: params[:account_id]) if params[:account_id].present?
    scope = scope.where("occurred_at >= ?", params[:from]) if params[:from].present?
    scope = scope.where("occurred_at <= ?", params[:to]) if params[:to].present?
    scope = apply_search(scope, params[:q])

    # Preload do que o serialize toca por transação (conta, tags, estornos) —
    # sem isso a listagem faz ~3 queries por item.
    transactions = scope.includes(:account, :tags, refunds_received: :refund_transaction)
                        .order(occurred_at: :desc, created_at: :desc)

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
      ai_status:             "analyzed", # entrada manual não passa por IA
      consolidated_at:       Time.current,
      created_by_membership: current_membership
    )
    transaction.save!
    apply_tags(transaction, params[:tag_ids]) if params.key?(:tag_ids)
    render json: { transaction: serialize(transaction) }, status: :created
  rescue ArgumentError => e
    # Date.parse inválida — ParameterMissing e RecordInvalid sobem pro rescue_from.
    render_validation_message(e.message)
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
  end

  # DELETE /api/v1/transactions/:id — exclusão definitiva (RF2.3 remover).
  def destroy
    @transaction.destroy!
    head :no_content
  rescue ActiveRecord::StaleObjectError
    # Outra pessoa mexeu na transação no meio do caminho — recarregue e refaça.
    render_already_decided(@transaction.reload)
  end

  # POST /api/v1/transactions/:id/consolidate — aceitar (RF2.3).
  def consolidate
    apply_decision("consolidated", :consolidated_at)
  end

  # POST /api/v1/transactions/:id/reject — rejeitar (RF2.3).
  def reject
    apply_decision("rejected", :rejected_at)
  end

  # GET /api/v1/transactions/:id/edits — trilha de alterações (RF4.3).
  def edits
    render json: { edits: @transaction.edits.recent.map { |e| serialize_edit(e) } }
  end

  # GET /api/v1/transactions/:id/source — payload cru do agregador (Pluggy) pra
  # "exibir mais detalhes" no app. Lazy (não vai na listagem).
  def source
    render json: { source: @transaction.source, source_metadata: @transaction.source_metadata }
  end

  # GET /api/v1/transactions/:id/refund_candidates — gastos que :id (credit)
  # pode estar estornando (RF10.1). Heurística por valor + recência.
  def refund_candidates
    candidates = Refunds::Candidates.call(credit: @transaction)
    render json: { refund_candidates: candidates.map { |t| serialize(t) } }
  end

  # POST /api/v1/transactions/:id/link_refund { refunded_transaction_id } — vincula
  # o estorno :id (credit) ao gasto informado (RF10.2). Confirmação humana (RF10.5).
  def link_refund
    debit = current_workspace.transactions.find(params.require(:refunded_transaction_id))
    Refunds::Link.call(credit: @transaction, debit: debit, membership: current_membership)
    render json: { transaction: serialize(@transaction.reload) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: { code: "invalid_refund", message: e.message } }, status: :unprocessable_entity
  end

  # POST /api/v1/transactions/reanalyze — RF3.5 botão "Reanalisar com IA".
  def reanalyze
    pending_count = current_workspace.transactions.where(status: "pending").count
    current_workspace.clear_ai_error! # nova tentativa → some o banner de erro
    AiSuggestion::ReanalyzeJob.perform_later(current_workspace.id)
    render json: { enqueued: true, pending_count: pending_count }, status: :accepted
  end

  # GET /api/v1/transactions/analysis_progress — progresso real da análise IA.
  # Estado explícito por tx (ai_status): queued (aguardando), analyzed (a IA rodou),
  # failed (não conseguiu). `done` quando NÃO há ninguém aguardando — failed não
  # trava o progresso. Counts indexados (ws,status,ai_status).
  def analysis_progress
    pending  = current_workspace.transactions.where(status: "pending")
    counts   = pending.group(:ai_status).count
    queued   = counts["queued"]   || 0
    analyzed = counts["analyzed"] || 0
    failed   = counts["failed"]   || 0
    render json: {
      total: queued + analyzed + failed,
      analyzed: analyzed, failed: failed, awaiting: queued,
      done: queued.zero?,
      error: current_workspace.ai_error_payload # {reason, message, at} | null
    }
  end

  # POST /api/v1/transactions/bulk_consolidate { ids: [...] } — aceita várias
  # pendentes de uma vez (RF2.3). Uma query (update_all) no lugar de N requests.
  def bulk_consolidate
    render json: { count: bulk_apply_status!("consolidated", consolidated_at: Time.current) }
  end

  # POST /api/v1/transactions/bulk_reject { ids: [...] } — rejeita várias de uma vez.
  def bulk_reject
    render json: { count: bulk_apply_status!("rejected", rejected_at: Time.current) }
  end

  private

  # Aplica status a várias transações do workspace de uma vez. Escopo em
  # current_workspace (segurança) e só em "pending" (idempotente; não revive
  # rejeitadas/consolidadas). update_all não dispara callbacks — consolidate e
  # reject são só status + timestamp, então é seguro e bem mais rápido.
  def bulk_apply_status!(status, **timestamps)
    ids = Array(params[:ids]).map(&:to_s).uniq
    return 0 if ids.empty?

    current_workspace.transactions
                     .where(id: ids, status: "pending")
                     .update_all({ status: status, updated_at: Time.current }.merge(timestamps))
  end

  def set_transaction
    @transaction = current_workspace.transactions.find(params[:id])
  end

  # Aceitar/rejeitar com "semáforo" pra uso simultâneo (casal, web + Telegram):
  #   - já no estado-alvo  → 200 idempotente (duplo toque, sem efeito colateral)
  #   - já decidido diferente → 409 sem sobrescrever (preserva a decisão do outro)
  #   - corrida pura (dois commits ao mesmo tempo) → o optimistic lock
  #     (lock_version) levanta StaleObjectError no perdedor → 409 (em vez de 500)
  STATUS_PT = { "consolidated" => "consolidado", "rejected" => "rejeitado" }.freeze

  def apply_decision(target, timestamp_attr)
    return render json: { transaction: serialize(@transaction) } if @transaction.status == target
    return render_already_decided(@transaction) unless @transaction.pending?

    @transaction.update!(status: target, timestamp_attr => Time.current)
    render json: { transaction: serialize(@transaction) }
  rescue ActiveRecord::StaleObjectError
    render_already_decided(@transaction.reload)
  end

  def render_already_decided(transaction)
    render json: {
      error: {
        code:    "already_decided",
        message: "Gasto já #{STATUS_PT[transaction.status] || transaction.status}. Recarregue o inbox."
      },
      transaction: serialize(transaction)
    }, status: :conflict
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

  # Código da moeda ORIGINAL quando a compra foi em moeda diferente da conta
  # (ex.: "USD"); nil quando foi na própria moeda. O amount_cents já está
  # convertido pra moeda da conta (BRL); isso é só pra sinalizar no card.
  def foreign_currency_for(t)
    code = t.source_metadata&.dig("currencyCode")
    base = t.account&.currency.presence || "BRL"
    code if code.present? && code.to_s.upcase != base.to_s.upcase
  end

  # Data da compra (YYYY-MM-DD) extraída do raw do Pluggy; nil quando ausente
  # (conta corrente, OFX, manual) ou timestamp inválido.
  def purchase_date_for(t)
    raw = t.source_metadata&.dig("creditCardMetadata", "purchaseDate")
    return nil if raw.blank?

    Date.parse(raw.to_s).iso8601
  rescue ArgumentError
    nil
  end

  def serialize(t)
    {
      id:                   t.id,
      account_id:           t.account_id,
      account_name:         t.account&.name,
      # RF2.7 — fonte do gasto: tipo (cartão/conta) + banco + bandeira/dígitos.
      account_kind:             t.account&.kind,
      institution_label:        BankConnections::Serializer::INSTITUTION_LABELS[t.account&.institution],
      account_institution_name: t.account&.institution_name,
      account_brand:            t.account&.card_brand,
      account_last_digits:      t.account&.last_digits,
      # Cartão da PRÓPRIA compra (Nubank tem cartões virtuais c/ dígitos distintos
      # sob a mesma conta) — vem do payload da transação, não da conta.
      card_last_digits:         t.source_metadata&.dig("creditCardMetadata", "cardNumber"),
      direction:            t.direction,
      amount_cents:         t.amount_cents,
      currency:             t.currency,
      # Moeda original quando a compra foi em outra moeda (chip "USD" no card);
      # null em compra na moeda da conta. amount_cents já vem convertido.
      foreign_currency:     foreign_currency_for(t),
      occurred_at:          t.occurred_at.iso8601,
      original_description: t.original_description,
      improved_title:       t.improved_title,
      ai_confidence:        confidence_label(t.ai_confidence),
      ai_suggestion:        t.ai_suggestion,
      ai_status:            t.ai_status,
      status:               t.status,
      source:               t.source,
      installment_number:   t.installment_number,
      installment_total:    t.installment_total,
      installment_group_id: t.installment_group_id,
      # RF9.4 — data da COMPRA (creditCardMetadata.purchaseDate do Pluggy): a
      # mesma pra todas as parcelas, usada pra exibir/ordenar o parcelamento
      # agregado (occurred_at é a data de cada parcela, mensal). null fora disso.
      purchase_date:        purchase_date_for(t),
      lock_version:         t.lock_version,
      # sort_by (não .order) pra aproveitar o preload da listagem — .order
      # dispararia uma query nova por transação mesmo com includes.
      tags:                 t.tags.sort_by(&:name).map { |tag| { id: tag.id, name: tag.name, color: tag.color, icon: tag.icon } },
      # RF10 — valor efetivo (desconta estornos) + resumo dos estornos recebidos.
      effective_amount_cents: t.effective_amount_cents,
      refund:                 serialize_refund(t)
    }
  end

  # RF10 — para um gasto estornado, expõe quanto e quais estornos; nil se não há.
  def serialize_refund(t)
    return nil if t.refunds_received.empty?

    {
      refunded_amount_cents: t.refunded_amount_cents,
      refunds: t.refunds_received.map do |r|
        { id: r.id, refund_transaction_id: r.refund_transaction_id,
          amount_cents: r.refund_transaction.amount_cents, confirmed_at: r.confirmed_at.iso8601 }
      end
    }
  end
end
