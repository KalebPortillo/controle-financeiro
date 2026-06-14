module Transactions
  # Conserta grupos de parcelamento inconsistentes (backfill idempotente):
  #   1. Recomputa `installment_group_id` com a chave nova (por `purchaseDate` do
  #      Pluggy) — desfaz colisões em que compras distintas no mesmo
  #      estabelecimento+total tinham caído no mesmo grupo.
  #   2. Remove parcelas PROJETADAS duplicadas: o Pluggy às vezes emite a parcela
  #      futura com `id` próprio e purchaseDate sintético (fura o dedup). Quando
  #      existe a parcela canônica equivalente, a projetada (pending) é apagada.
  #
  # Seguro de re-rodar. Retorna { regrouped:, removed: }.
  module RegroupInstallments
    module_function

    def call(scope: Transaction.where.not(installment_total: nil))
      { regrouped: regroup(scope), removed: remove_projected_duplicates(scope) }
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

    def remove_projected_duplicates(scope)
      count = 0
      scope.find_each do |t|
        next unless t.status == "pending"
        next unless Installment.projected?(t.source_metadata, t.occurred_at)
        next unless canonical_sibling?(t)

        t.destroy!
        count += 1
      end
      count
    end

    # Existe outra parcela com mesma conta+total+número, mesmo estabelecimento
    # (descritor normalizado) e que NÃO é projetada (tem a compra real)?
    def canonical_sibling?(t)
      desc = Recurrences::Descriptor.normalize(t.original_description)
      Transaction
        .where(account_id: t.account_id, installment_total: t.installment_total, installment_number: t.installment_number)
        .where.not(id: t.id)
        .any? do |s|
          Recurrences::Descriptor.normalize(s.original_description) == desc &&
            !Installment.projected?(s.source_metadata, s.occurred_at)
        end
    end
  end
end
