class CreateRecurrenceExclusions < ActiveRecord::Migration[8.0]
  def change
    create_table :recurrence_exclusions, id: :uuid do |t|
      t.references :recurrence,  null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :transaction, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :workspace,   null: false, type: :uuid, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    # Uma transação só pode ser excluída uma vez de cada recorrência.
    add_index :recurrence_exclusions, [ :recurrence_id, :transaction_id ], unique: true,
              name: "index_recurrence_exclusions_uniqueness"
  end
end
