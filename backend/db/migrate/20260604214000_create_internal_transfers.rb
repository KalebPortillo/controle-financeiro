class CreateInternalTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :internal_transfers, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      # Cada transação participa de no máximo uma transferência (→ unique).
      t.references :debit_transaction, null: false, type: :uuid,
                   foreign_key: { to_table: :transactions }, index: { unique: true }
      t.references :credit_transaction, null: false, type: :uuid,
                   foreign_key: { to_table: :transactions }, index: { unique: true }
      # null = detectado automaticamente (RF11.1); preenchido se marcado por humano.
      t.references :confirmed_by_membership, type: :uuid,
                   foreign_key: { to_table: :workspace_memberships }
      t.datetime :detected_at, null: false

      t.timestamps
    end
  end
end
