class CreateImports < ActiveRecord::Migration[8.1]
  def change
    create_table :imports, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :uploaded_by_membership, null: false, type: :uuid,
                   foreign_key: { to_table: :workspace_memberships }
      # Conta opcional: o usuário pode associar ao subir (senão vai p/ a conta manual).
      t.references :account, null: true, type: :uuid, foreign_key: true

      t.string  :filename, null: false
      t.string  :format, null: false
      t.integer :file_size_bytes, null: false, default: 0
      t.string  :status, null: false, default: "pending"
      t.integer :created_count,   null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.integer :error_count,     null: false, default: 0
      t.jsonb   :error_log
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :imports, [ :workspace_id, :created_at ]
    add_check_constraint :imports, "format IN ('csv', 'ofx')", name: "imports_format_check"
    add_check_constraint :imports,
      "status IN ('pending', 'processing', 'completed', 'failed')", name: "imports_status_check"
  end
end
