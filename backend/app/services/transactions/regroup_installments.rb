module Transactions
  # Conserta grupos de parcelamento inconsistentes (backfill idempotente):
  #   1. Recomputa `installment_group_id` com a chave nova (por `purchaseDate` do
  #      Pluggy) — desfaz colisões em que compras distintas no mesmo
  #      estabelecimento+total tinham caído no mesmo grupo.
  #   2. Rejeita parcelas PROJETADAS duplicadas: o Pluggy às vezes emite a parcela
  #      futura com `id` próprio e purchaseDate sintético (fura o dedup). Quando
  #      existe a parcela canônica equivalente, a projetada (pending) é rejeitada
  #      — NÃO deletada: a linha rejeitada some da inbox e, por persistir, o dedup
  #      por `id` impede o reimport no próximo sync.
  #
  # Seguro de re-rodar. Retorna { regrouped:, rejected: }.
  module RegroupInstallments
    module_function

    def call(scope: Transaction.where.not(installment_total: nil))
      { regrouped: regroup(scope), rejected: reject_projected_duplicates(scope) }
    end

    def regroup(scope)
      count = 0
      scope.find_each do |t|
        new_id = Installment.group_id(
          account_id:  t.account_id,
          description: t.original_description,
          total:       t.installment_total,
          raw:         t.source_metadata
        )
        next if new_id == t.installment_group_id

        t.update_columns(installment_group_id: new_id) # rubocop:disable Rails/SkipsModelValidations
        count += 1
      end
      count
    end

    def reject_projected_duplicates(scope)
      count = 0
      scope.find_each do |t|
        next unless t.status == "pending"
        next unless Installment.projected?(t.source_metadata, t.occurred_at)
        next unless Installment.canonical_exists?(
          Transaction.where(account_id: t.account_id),
          total: t.installment_total, number: t.installment_number,
          description: t.original_description, exclude_id: t.id
        )

        t.update_columns(status: "rejected", rejected_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        count += 1
      end
      count
    end
  end
end
