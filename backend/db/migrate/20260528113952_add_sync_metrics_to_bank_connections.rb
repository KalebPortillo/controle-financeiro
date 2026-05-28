class AddSyncMetricsToBankConnections < ActiveRecord::Migration[8.1]
  # Métricas da última sincronização (RF21.2). Denormalizadas na conexão —
  # histórico completo das últimas N execuções (RF21.7) fica pra depois,
  # numa tabela sync_runs própria.
  def change
    change_table :bank_connections, bulk: true do |t|
      t.integer :last_sync_created_count,    null: false, default: 0
      t.integer :last_sync_duplicate_count,  null: false, default: 0
      t.integer :last_sync_error_count,      null: false, default: 0
      t.integer :last_sync_duration_seconds
      t.datetime :next_sync_at
    end
  end
end
