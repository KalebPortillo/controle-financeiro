class AddAiStatusToTransactions < ActiveRecord::Migration[8.1]
  # Estado EXPLÍCITO da análise IA de cada transação (RF3/RF22):
  #   queued   — aguardando análise (recém-criada / re-enfileirada)
  #   analyzed — a IA processou (com ou sem sugestão útil)
  #   failed   — a IA não conseguiu (indisponível/desistiu); NÃO está aguardando
  # Antes "analisada" era só `ai_suggestion` presente, o que confundia
  # "aguardando" com "falhou" e travava o progresso. Ver Transaction::AI_STATUSES.
  def up
    add_column :transactions, :ai_status, :string, null: false, default: "queued"
    add_index :transactions, [ :workspace_id, :status, :ai_status ],
              name: "index_transactions_on_ws_status_ai_status"

    # Backfill: o que tem sugestão já foi analisado; o resto (pending sem sugestão)
    # não está aguardando ninguém → marca como failed (some do limbo "Analisando…",
    # vira "não analisado" com retry). Consolidadas/rejeitadas → analyzed (terminais).
    execute(<<~SQL.squish)
      UPDATE transactions SET ai_status = 'analyzed'
      WHERE ai_suggestion IS NOT NULL OR status <> 'pending';
    SQL
    execute(<<~SQL.squish)
      UPDATE transactions SET ai_status = 'failed'
      WHERE ai_suggestion IS NULL AND status = 'pending';
    SQL
  end

  def down
    remove_index :transactions, name: "index_transactions_on_ws_status_ai_status"
    remove_column :transactions, :ai_status
  end
end
