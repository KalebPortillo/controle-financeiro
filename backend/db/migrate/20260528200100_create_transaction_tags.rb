class CreateTransactionTags < ActiveRecord::Migration[8.1]
  def change
    create_table :transaction_tags, id: :uuid do |t|
      t.references :transaction, type: :uuid, null: false, foreign_key: true
      t.references :tag,         type: :uuid, null: false, foreign_key: true

      t.timestamps
    end

    # Uma tag não se repete na mesma transação (RF5.2).
    add_index :transaction_tags, [ :transaction_id, :tag_id ], unique: true
  end
end
