class CreateBankConnections < ActiveRecord::Migration[8.1]
  def change
    # `provider` e `status` são enums no nível do app (string + CHECK no DB,
    # mesmo padrão de workspace_memberships.role — fácil de evoluir).
    create_table :bank_connections, id: :uuid do |t|
      t.references :workspace,        type: :uuid, null: false, foreign_key: true
      t.references :owner_membership, type: :uuid, null: false,
                                      foreign_key: { to_table: :workspace_memberships }
      t.string   :provider,               null: false, default: "pluggy"
      t.string   :external_connection_id, null: false
      t.string   :credentials_ref
      t.string   :status,                 null: false, default: "connected"
      t.datetime :last_sync_at
      t.text     :error_message
      t.date     :sync_history_since,     null: false

      t.timestamps
    end

    add_index :bank_connections, [ :provider, :external_connection_id ], unique: true
    add_check_constraint :bank_connections,
                         "provider IN ('pluggy', 'manual')",
                         name: "bank_connections_provider_check"
    add_check_constraint :bank_connections,
                         "status IN ('connected', 'syncing', 'expired', 'error', 'disconnected')",
                         name: "bank_connections_status_check"
  end
end
