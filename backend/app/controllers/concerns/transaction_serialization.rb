# Serialização canônica de uma transação para o front (inbox, consolidados,
# relatórios). Extraído do TransactionsController para ser reusado por controllers
# que também devolvem listas de transações (ex.: drill-down de relatórios), de
# modo que o front reaproveite os mesmos componentes de linha/detalhe.
#
# Requer `current_workspace` (ApplicationController). As memoizações
# (@recurrence_index/@recurrence_exclusion_pairs) são por request, então uma
# listagem não faz uma query por transação.
module TransactionSerialization
  extend ActiveSupport::Concern

  # Preload do que o serialize toca por transação (conta, tags, estornos,
  # vínculos) — sem isso a listagem faz ~3 queries por item.
  SERIALIZE_INCLUDES = [
    :account, :tags,
    { refunds_received: :refund_transaction },
    { refund_of: :refunded_transaction },
    { related_links: :related_transaction },
    { link_as_related: :primary_transaction }
  ].freeze

  private

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
      foreign_currency:     t.foreign_currency,
      # RF2.7 — linha de ajuste do agregador (Pluggy), não é compra real.
      aggregator_adjustment: t.aggregator_adjustment?,
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
      refund:                 serialize_refund(t),
      # RF23 — transações relacionadas (IOF/tarifa…): satélites deste gasto e/ou
      # o gasto de origem quando esta é o satélite.
      related:                serialize_related(t),
      # RF9.7 — a recorrência a que este gasto pertence (pra sinalizar/gerenciar
      # no detalhe); null quando não faz parte de nenhuma.
      recurrence:             serialize_recurrence(t)
    }
  end

  def confidence_label(value)
    return nil if value.nil?
    if value >= 0.8 then "high"
    elsif value >= 0.5 then "medium"
    else "low"
    end
  end

  # Data da compra (YYYY-MM-DD) extraída do raw do Pluggy; nil quando ausente
  # (conta corrente, OFX, manual) ou timestamp inválido.
  def purchase_date_for(t)
    # Parcela: usa a data da compra RETRO-CALCULADA (occurred − (número−1) meses),
    # nunca o purchaseDate do Pluggy — que nas parcelas projetadas é SINTÉTICO (= a
    # data da fatura de cada parcela, no futuro). Isso mantém a data exibida = data
    # da compra (passado), coerente com o group_id. Ver Transactions::Installment.
    if t.installment_number && t.installment_total
      anchor = Transactions::Installment.purchase_anchor(number: t.installment_number, occurred: t.occurred_at)
      return anchor if anchor
    end

    raw = t.source_metadata&.dig("creditCardMetadata", "purchaseDate")
    return nil if raw.blank?

    Date.parse(raw.to_s).iso8601
  rescue ArgumentError
    nil
  end

  # RF9.7 — recorrência deste gasto (débito cujo descritor normalizado casa o
  # padrão de uma recorrência da conta e que não foi excluído do grupo).
  def serialize_recurrence(t)
    r = recurrence_for(t)
    r && { id: r.id, descriptor_pattern: r.descriptor_pattern }
  end

  def recurrence_for(t)
    return nil unless t.direction == "debit"

    r = recurrence_index[[ t.account_id, Recurrences::Descriptor.normalize(t.original_description) ]]
    return nil if r.nil? || recurrence_exclusion_pairs.include?([ r.id, t.id ])

    r
  end

  # (account_id, descriptor_pattern) => Recurrence — memoizado por request pra a
  # listagem não fazer uma query por transação.
  def recurrence_index
    @recurrence_index ||= current_workspace.recurrences.each_with_object({}) do |r, acc|
      acc[[ r.account_id, r.descriptor_pattern ]] = r
    end
  end

  def recurrence_exclusion_pairs
    @recurrence_exclusion_pairs ||=
      RecurrenceExclusion.where(recurrence_id: recurrence_index.values.map(&:id))
                         .pluck(:recurrence_id, :transaction_id).to_set
  end

  # RF23 — vínculos desta transação. Como origem: lista os satélites (role
  # "satellite"). Como satélite: aponta o gasto de origem (role "origin").
  def serialize_related(t)
    items =
      t.related_links.map { |l| related_item(l, l.related_transaction, "satellite", l.id) } +
      Array(t.link_as_related).map { |l| related_item(l, l.primary_transaction, "origin", l.id) } +
      refund_related_items(t)
    items.presence
  end

  def related_item(link, other, role, link_id)
    {
      link_id:       link_id,
      link_kind:     "link",
      relation_type: link.relation_type,
      role:          role,
      transaction_id: other.id,
      title:         other.improved_title.presence || other.original_description,
      direction:     other.direction,
      amount_cents:  other.amount_cents,
      occurred_at:   other.occurred_at.iso8601,
      status:        other.status
    }
  end

  # RF10.6 — o vínculo de estorno também flui por `related` pra aninhar o estorno
  # sob a compra no inbox: compra estornada → satélites "refund" (os créditos);
  # crédito de estorno → origem "refund" (a compra).
  def refund_related_items(t)
    as_anchor = t.refunds_received.map { |r| refund_related_item(r, r.refund_transaction, "satellite") }
    as_refund = Array(t.refund_of).map { |r| refund_related_item(r, r.refunded_transaction, "origin") }
    as_anchor + as_refund
  end

  def refund_related_item(refund, other, role)
    {
      link_id:       refund.id,
      link_kind:     "refund",
      relation_type: "refund",
      origin:        refund.origin,
      confidence:    refund.confidence,
      role:          role,
      transaction_id: other.id,
      title:         other.improved_title.presence || other.original_description,
      direction:     other.direction,
      amount_cents:  other.amount_cents,
      occurred_at:   other.occurred_at.iso8601,
      status:        other.status
    }
  end

  # RF10 — para um gasto estornado, expõe quanto e quais estornos; nil se não há.
  def serialize_refund(t)
    return nil if t.refunds_received.empty?

    {
      refunded_amount_cents: t.refunded_amount_cents,
      refunds: t.refunds_received.map do |r|
        { id: r.id, refund_transaction_id: r.refund_transaction_id,
          amount_cents: r.refund_transaction.amount_cents, confirmed_at: r.confirmed_at.iso8601,
          origin: r.origin, confidence: r.confidence }
      end
    }
  end
end
