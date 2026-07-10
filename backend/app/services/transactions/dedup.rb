module Transactions
  # Limpeza única das duplicatas de CONTEÚDO criadas antes da reconciliação por
  # assinatura (compra de cartão que passou de PENDING pra POSTED ganhou id novo
  # no Pluggy e furou o dedup por id). Agrupa transações automatic_sync idênticas
  # em (conta, data, valor, direção, descrição), elege 1 sobrevivente (a mais
  # "rica": com vínculos de IOF/estorno, edições, consolidada) e FUNDE as demais
  # nela — migra vínculos, título, tags e status — antes de removê-las. Idempotente.
  #
  # Uso: `plan` (dry-run, não altera nada) e `run!` (aplica). Ver rake transactions:dedup.
  module Dedup
    module_function

    SIGNATURE = %i[account_id occurred_at amount_cents direction original_description].freeze

    Group = Data.define(:key, :survivor, :doomed)

    # [Group, ...] — grupos com mais de uma linha idêntica. Não altera nada.
    def plan
      Transaction.where(source: "automatic_sync")
                 .group(SIGNATURE).having("COUNT(*) > 1").count.keys.map do |key|
        rows = Transaction.where(SIGNATURE.zip(key).to_h).order(:created_at).to_a
        survivor = pick_survivor(rows)
        Group.new(key: key, survivor: survivor, doomed: rows - [ survivor ])
      end
    end

    # Aplica a fusão + remoção. Retorna o total de linhas removidas.
    def run!
      removed = 0
      plan.each do |group|
        Transaction.transaction do
          group.doomed.each do |doomed|
            merge_into!(group.survivor, doomed)
            doomed.destroy!
            removed += 1
          end
        end
      end
      removed
    end

    # A "mais rica": prioriza quem carrega vínculos (difíceis de refazer), depois
    # edições humanas, depois consolidada; empata pela mais antiga.
    def pick_survivor(rows)
      rows.max_by do |r|
        [
          r.related_links.size + (r.link_as_related ? 1 : 0) +
            r.refunds_received.size + (r.refund_of ? 1 : 0),
          r.edits.size,
          r.consolidated? ? 1 : 0,
          -r.created_at.to_i
        ]
      end
    end

    # Traz pro sobrevivente tudo que só existe na duplicata, respeitando os
    # índices únicos (related+relation_type; refund_transaction_id).
    def merge_into!(survivor, doomed)
      if survivor.improved_title.blank? && doomed.improved_title.present?
        survivor.update_column(:improved_title, doomed.improved_title)
      end

      (doomed.tags - survivor.tags).each { |tag| survivor.tags << tag }

      if !survivor.consolidated? && doomed.consolidated?
        survivor.update_columns(status: "consolidated",
                                consolidated_at: doomed.consolidated_at || Time.current)
      end

      # RF23 — doomed como primário de um satélite (IOF/tarifa): re-aponta pro
      # sobrevivente (o índice único é por related+tipo, não por primário → seguro).
      doomed.related_links.find_each { |link| link.update_column(:primary_transaction_id, survivor.id) }

      # doomed como satélite: só migra se o sobrevivente ainda não tem esse tipo.
      if (sat = doomed.link_as_related) &&
         !TransactionLink.exists?(related_transaction_id: survivor.id, relation_type: sat.relation_type)
        sat.update_column(:related_transaction_id, survivor.id)
      end

      # RF10 — doomed é o crédito (estorno): migra se o sobrevivente não for estorno.
      if (refund = doomed.refund_of) && survivor.refund_of.nil?
        refund.update_column(:refund_transaction_id, survivor.id)
      end

      # doomed é o débito estornado: os estornos recebidos passam pro sobrevivente.
      doomed.refunds_received.find_each { |r| r.update_column(:refunded_transaction_id, survivor.id) }
    end
  end
end
