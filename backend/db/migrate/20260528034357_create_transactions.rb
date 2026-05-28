class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :account,   type: :uuid, null: false, foreign_key: true

      t.string  :direction,            null: false                    # debit | credit
      t.integer :amount_cents,         null: false                    # sempre positivo
      t.string  :currency,             null: false, default: "BRL", limit: 3
      t.date    :occurred_at,          null: false                    # RF14.2
      t.text    :original_description, null: false
      t.text    :improved_title                                       # AI/usuário
      t.string  :status,               null: false, default: "pending" # inbox
      t.string  :source,               null: false                    # automatic_sync | ...
      t.jsonb   :source_metadata                                      # payload bruto

      t.references :created_by_membership, type: :uuid, null: true,
                                           foreign_key: { to_table: :workspace_memberships }
      t.references :parent_transaction,    type: :uuid, null: true,
                                           foreign_key: { to_table: :transactions }

      t.decimal  :ai_confidence, precision: 3, scale: 2               # 0.00–1.00
      t.integer  :installment_number, limit: 2                       # RF9.4
      t.integer  :installment_total,  limit: 2
      t.uuid     :installment_group_id
      t.datetime :consolidated_at
      t.datetime :rejected_at
      t.integer  :lock_version, null: false, default: 0              # optimistic lock

      t.timestamps
    end

    # external_transaction_id: id da transação no agregador (Pluggy), extraído
    # do source_metadata jsonb como coluna gerada. Base do dedup de sync
    # (decisão em modelo-de-dados.md). GIN no jsonb fica de fora (overhead).
    execute <<~SQL
      ALTER TABLE transactions
        ADD COLUMN external_transaction_id text
        GENERATED ALWAYS AS (source_metadata->>'id') STORED
    SQL

    add_index :transactions, [ :account_id, :external_transaction_id ],
              unique: true, where: "external_transaction_id IS NOT NULL",
              name: "index_transactions_on_account_and_external_id"

    # Índices quentes (modelo-de-dados.md).
    add_index :transactions, [ :workspace_id, :status, :occurred_at ],
              order: { occurred_at: :desc },
              name: "index_transactions_on_workspace_status_occurred"
    add_index :transactions, [ :account_id, :occurred_at ]
    add_index :transactions, :installment_group_id

    add_check_constraint :transactions, "amount_cents > 0", name: "transactions_amount_positive"
    add_check_constraint :transactions,
                         "direction IN ('debit', 'credit')",
                         name: "transactions_direction_check"
    add_check_constraint :transactions,
                         "status IN ('pending', 'consolidated', 'rejected', 'split')",
                         name: "transactions_status_check"
    add_check_constraint :transactions,
                         "source IN ('automatic_sync', 'manual_import', 'manual_entry', 'installment_generated')",
                         name: "transactions_source_check"
    add_check_constraint :transactions,
                         "(installment_number IS NULL) = (installment_total IS NULL)",
                         name: "transactions_installment_pair_check"
  end
end
