class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    # Notificações in-app (RF17). recipient_membership NULL = broadcast pro
    # workspace inteiro (caso padrão do casal). `dedup_key` impede re-notificar
    # o mesmo fato (ex.: mesma recorrência atrasada todo dia) — unicidade
    # garantida no banco, não no app.
    create_table :notifications, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :recipient_membership, type: :uuid, null: true,
                                          foreign_key: { to_table: :workspace_memberships }
      t.string   :kind, null: false
      t.jsonb    :payload, null: false, default: {}
      t.string   :dedup_key
      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications, [ :recipient_membership_id, :read_at ]
    add_index :notifications, [ :workspace_id, :created_at ]
    add_index :notifications, [ :workspace_id, :dedup_key ], unique: true,
              where: "dedup_key IS NOT NULL", name: "index_notifications_dedup"

    add_check_constraint :notifications,
                         "kind IN ('inbox_new', 'budget_warning', 'budget_exceeded', " \
                         "'recurrent_missed', 'sync_failed', 'import_completed')",
                         name: "notifications_kind_check"
  end
end
