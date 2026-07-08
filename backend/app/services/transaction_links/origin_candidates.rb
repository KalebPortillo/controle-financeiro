module TransactionLinks
  # RF23 Fase 3 — dado um satélite (tarifa/juros/ajuste órfão), lista os gastos
  # do workspace que podem ser sua ORIGEM, pro vínculo manual. Heurística simples
  # (decisão é humana): mesma conta, exclui a própria transação e a que já é sua
  # origem, filtra por busca opcional (`q`), mais recentes primeiro. Até MAX.
  module OriginCandidates
    MAX = 15

    module_function

    def call(related:, q: nil)
      workspace = related.workspace
      scope = workspace.transactions.where.not(id: related.id)
      scope = scope.where(account_id: related.account_id) if related.account_id
      scope = scope.where.not(id: current_origin_ids(related))
      scope = scope.search(q) if q.present?
      scope.includes(:account, :tags, refunds_received: :refund_transaction,
                     related_links: :related_transaction, link_as_related: :primary_transaction)
           .order(occurred_at: :desc)
           .limit(MAX)
    end

    # Origem(ns) já vinculada(s) a este satélite — não faz sentido reoferecê-la(s).
    def current_origin_ids(related)
      TransactionLink.where(related_transaction_id: related.id).pluck(:primary_transaction_id)
    end
  end
end
