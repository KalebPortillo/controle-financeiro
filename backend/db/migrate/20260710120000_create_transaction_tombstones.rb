class CreateTransactionTombstones < ActiveRecord::Migration[8.0]
  # RF2.3 — quando o usuário exclui um gasto sincronizado, guardamos a assinatura
  # de conteúdo (conta+data+valor+direção+descrição) pra o sync NÃO ressuscitá-lo.
  # O `id` do Pluggy não é estável (PENDING→POSTED ganha id novo), então o dedup
  # por id não impede o retorno — a assinatura sim.
  def change
    create_table :transaction_tombstones, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :account,   null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.date    :occurred_at,          null: false
      t.integer :amount_cents,         null: false
      t.string  :direction,            null: false
      t.text    :original_description, null: false

      t.timestamps
    end

    add_index :transaction_tombstones,
              [ :account_id, :occurred_at, :amount_cents, :direction, :original_description ],
              name: "idx_transaction_tombstones_signature"
  end
end
