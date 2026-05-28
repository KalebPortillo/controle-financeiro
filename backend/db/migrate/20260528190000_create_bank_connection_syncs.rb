class CreateBankConnectionSyncs < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_connection_syncs, id: :uuid do |t|
      t.references :bank_connection, type: :uuid, null: false, foreign_key: true

      t.datetime :started_at,      null: false
      t.datetime :finished_at
      t.integer  :duration_seconds
      t.string   :status,          null: false               # success | error
      t.integer  :created_count,   null: false, default: 0
      t.integer  :duplicate_count, null: false, default: 0
      t.integer  :error_count,     null: false, default: 0
      t.text     :error_message

      t.timestamps
    end

    # Painel busca as últimas N por conexão, mais recentes primeiro (RF21.7).
    add_index :bank_connection_syncs, [ :bank_connection_id, :started_at ]
  end
end
