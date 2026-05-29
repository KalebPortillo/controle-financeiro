class CreateTransactionEdits < ActiveRecord::Migration[8.1]
  def change
    create_table :transaction_edits, id: :uuid do |t|
      t.references :transaction, type: :uuid, null: false, foreign_key: true
      t.references :edited_by_membership, type: :uuid, null: false,
                                          foreign_key: { to_table: :workspace_memberships }

      t.string :field_name, null: false   # improved_title | amount_cents | occurred_at | tags
      t.jsonb  :old_value                  # flexível: string, número, array
      t.jsonb  :new_value

      t.timestamps
    end

    # Histórico de um gasto, mais recente primeiro (RF4.3).
    add_index :transaction_edits, [ :transaction_id, :created_at ]
  end
end
