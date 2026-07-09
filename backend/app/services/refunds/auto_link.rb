module Refunds
  # RF10.6 — varre os estornos (créditos) ainda não vinculados e, quando há
  # match de código exato ÚNICO (Refunds::CodeMatch), aplica o estorno
  # automaticamente (origin "automatic", sem membership) e notifica. Idempotente:
  # créditos já vinculados são pulados. Roda no sync (após novos dados) e no
  # backfill `rails refunds:autolink`.
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
        next if duplicate_sibling?(credit) # duplicata do dado → ambíguo, não vincula

        debit = CodeMatch.call(credit: credit)
        next unless debit
        next if debit.refunded_amount_cents >= debit.amount_cents # já estornado

        link!(credit, debit)
        linked += 1
      end
      linked
    end

    private

    def unlinked_credits
      @workspace.transactions.where(direction: "credit").where.missing(:refund_of)
    end

    # Estorno idêntico repetido (mesmo valor+data+descrição) costuma ser duplicata
    # do agregador; auto-vincular os dois dobraria o abatimento — melhor deixar
    # como sugestão (o usuário decide).
    def duplicate_sibling?(credit)
      @workspace.transactions
                .where(direction: "credit", amount_cents: credit.amount_cents,
                       occurred_at: credit.occurred_at, original_description: credit.original_description)
                .where.not(id: credit.id)
                .exists?
    end

    def link!(credit, debit)
      TransactionRefund.create!(
        refund_transaction:   credit,
        refunded_transaction: debit,
        origin:               "automatic",
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
