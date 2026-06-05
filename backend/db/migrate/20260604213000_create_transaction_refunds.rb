class CreateTransactionRefunds < ActiveRecord::Migration[8.1]
  def change
    create_table :transaction_refunds, id: :uuid do |t|
      # A transação de crédito que é o estorno (uma por vínculo → unique).
      t.references :refund_transaction, null: false, type: :uuid,
                   foreign_key: { to_table: :transactions }, index: { unique: true }
      # O gasto (débito) que foi estornado.
      t.references :refunded_transaction, null: false, type: :uuid,
                   foreign_key: { to_table: :transactions }
      t.references :confirmed_by_membership, null: false, type: :uuid,
                   foreign_key: { to_table: :workspace_memberships }
      t.datetime :confirmed_at, null: false

      t.timestamps
    end
  end
end
