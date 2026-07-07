class CreateTransactionLinks < ActiveRecord::Migration[8.1]
  # RF23 — transações relacionadas (IOF, tarifa, juros, ajuste) ligadas ao gasto
  # de origem. Estorno continua em transaction_refunds; a view "relacionadas"
  # une os dois. Vínculo do IOF é auto-detectado (origin: automatic) no sync.
  def change
    create_table :transaction_links, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      # A âncora: o gasto de origem (ex.: a compra internacional).
      t.references :primary_transaction, null: false, type: :uuid,
                   foreign_key: { to_table: :transactions }
      # O satélite: IOF/tarifa/juros/ajuste. Único por (related, relation_type).
      t.references :related_transaction, null: false, type: :uuid,
                   foreign_key: { to_table: :transactions }
      t.string :relation_type, null: false
      t.string :origin, null: false, default: "automatic"
      t.decimal :confidence, precision: 3, scale: 2
      t.references :confirmed_by_membership, type: :uuid,
                   foreign_key: { to_table: :workspace_memberships }
      t.timestamps
    end

    add_index :transaction_links, [ :related_transaction_id, :relation_type ], unique: true,
              name: "index_transaction_links_on_related_and_type"

    add_check_constraint :transaction_links,
      "relation_type IN ('iof','fee','interest','adjustment')", name: "transaction_links_relation_type_check"
    add_check_constraint :transaction_links,
      "origin IN ('automatic','manual')", name: "transaction_links_origin_check"
  end
end
