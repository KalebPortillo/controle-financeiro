namespace :installments do
  # Backfill que conserta grupos de parcelamento inconsistentes:
  #   - recomputa installment_group_id pela chave nova (purchaseDate do Pluggy),
  #     desfazendo colisões entre compras distintas no mesmo lugar+total;
  #   - rejeita parcelas projetadas duplicadas (purchaseDate sintético sem MCC)
  #     quando há a parcela canônica.
  # Idempotente. Uso: bin/rails installments:regroup
  desc "Reagrupa parcelamentos pela chave purchaseDate e rejeita duplicatas projetadas"
  task regroup: :environment do
    result = Transactions::RegroupInstallments.call
    puts "[installments:regroup] regrouped=#{result[:regrouped]} rejected=#{result[:rejected]}"
  end
end
