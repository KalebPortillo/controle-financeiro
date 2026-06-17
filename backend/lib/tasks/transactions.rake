namespace :transactions do
  # Conserta gastos em moeda estrangeira que entraram com o valor NOMINAL (ex.:
  # USD) como se fosse BRL — recalcula a partir do amountInAccountCurrency do
  # Pluggy guardado no source_metadata. Idempotente; rodar uma vez pós-deploy.
  #
  # Uso: bin/rails transactions:backfill_foreign_currency
  desc "Recalcula gastos em moeda estrangeira usando amountInAccountCurrency (idempotente)"
  task backfill_foreign_currency: :environment do
    result = Transactions::BackfillForeignCurrency.call
    puts "[transactions:backfill_foreign_currency] corrigidos=#{result[:fixed]} ignorados=#{result[:skipped]}"
  end
end
