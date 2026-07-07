namespace :transaction_links do
  # RF23 — backfill: liga IOFs de compra internacional já importados ao gasto de
  # origem (compra em moeda estrangeira), pela alíquota fixa de 3,5%. Idempotente.
  # Uso: bin/rails transaction_links:detect_iof
  desc "Detecta e vincula IOFs de compra internacional às compras de origem"
  task detect_iof: :environment do
    total = 0
    Workspace.find_each do |ws|
      n = TransactionLinks::DetectIof.call(workspace: ws)
      total += n
      puts "  workspace #{ws.id[0, 8]} (#{ws.name}): #{n} vínculos" if n.positive?
    end
    puts "[transaction_links:detect_iof] total de vínculos criados: #{total}"
  end
end
