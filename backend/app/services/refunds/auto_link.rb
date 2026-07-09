module Refunds
  # RF10.6 — varre os estornos (créditos) ainda não vinculados e, quando a
  # heurística de confiança (Refunds::Match) acha o gasto original, aplica o
  # estorno automaticamente (origin "automatic", sem membership, com confidence
  # high/medium) e notifica. Idempotente: créditos já vinculados são pulados.
  # Roda no sync (após novos dados) e no backfill `rails refunds:autolink`.
  class AutoLink
    def self.call(**kwargs)
      new(**kwargs).call
    end

    # `notify: false` no backfill em lote — dezenas de avisos de uma vez viram
    # spam; o usuário revê os vínculos no app. No sync ao vivo, notifica (RF10.6).
    def initialize(workspace:, notify: true)
      @workspace = workspace
      @notify    = notify
    end

    # Retorna quantos estornos foram vinculados nesta passagem.
    def call
      linked = 0
      unlinked_credits.find_each do |credit|
        match = Match.call(credit: credit)
        next unless match
        next if match.debit.refunded_amount_cents >= match.debit.amount_cents # já estornado

        link!(credit, match.debit, match.confidence)
        linked += 1
      end
      linked
    end

    private

    def unlinked_credits
      @workspace.transactions.where(direction: "credit").where.missing(:refund_of)
    end

    def link!(credit, debit, confidence)
      TransactionRefund.create!(
        refund_transaction:   credit,
        refunded_transaction: debit,
        origin:               "automatic",
        confidence:           confidence.to_s,
        confirmed_at:         Time.current
      )
      notify(credit, debit) if @notify
    end

    def notify(credit, debit)
      Notifications::Create.call(
        workspace: @workspace,
        kind:      "refund_auto_linked",
        dedup_key: "refund_auto_linked:#{credit.id}",
        payload: {
          refund_transaction_id:   credit.id,
          refunded_transaction_id: debit.id,
          refunded_title:          debit.improved_title.presence || debit.original_description,
          amount_cents:            credit.amount_cents
        }
      )
    end
  end
end
