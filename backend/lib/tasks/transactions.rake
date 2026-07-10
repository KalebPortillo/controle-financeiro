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

  # Limpa duplicatas de conteúdo (compra PENDING→POSTED que ganhou id novo no
  # Pluggy antes da reconciliação por assinatura). Por padrão é DRY-RUN: só lista
  # o que faria. Pra aplicar de fato, passe CONFIRM=1. Idempotente.
  #
  # Uso:  bin/rails transactions:dedup            # dry-run (não altera nada)
  #       CONFIRM=1 bin/rails transactions:dedup  # aplica a fusão + remoção
  desc "Deduplica transações idênticas (PENDING→POSTED com id novo). DRY-RUN por padrão; CONFIRM=1 aplica"
  task dedup: :environment do
    plan = Transactions::Dedup.plan
    excess = plan.sum { |g| g.doomed.size }
    puts "[transactions:dedup] grupos=#{plan.size} linhas_excedentes=#{excess}"

    plan.first(1000).each do |g|
      _acc, date, cents, dir, desc = g.key
      puts "  [#{date}] #{dir} R$#{format('%.2f', cents / 100.0)}  #{desc.to_s[0, 45]}"
      puts "    KEEP #{g.survivor.id} (#{g.survivor.status})"
      g.doomed.each { |d| puts "    DROP #{d.id} (#{d.status})" }
    end

    if ENV["CONFIRM"] == "1"
      removed = Transactions::Dedup.run!
      puts "[transactions:dedup] APLICADO — removidas=#{removed}"
    else
      puts "[transactions:dedup] DRY-RUN — nada alterado. Rode com CONFIRM=1 pra aplicar."
    end
  end
end
