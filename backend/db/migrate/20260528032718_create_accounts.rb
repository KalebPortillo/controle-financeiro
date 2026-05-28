class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts, id: :uuid do |t|
      t.references :workspace,        type: :uuid, null: false, foreign_key: true
      t.references :owner_membership, type: :uuid, null: false,
                                      foreign_key: { to_table: :workspace_memberships }
      # Nullable: contas manuais (RF12) não vêm de um agregador.
      t.references :bank_connection, type: :uuid, null: true, foreign_key: true
      t.string :name,        null: false
      t.string :kind,        null: false
      t.string :institution, null: false
      t.string :external_id  # id da conta no Pluggy (null em manual)
      t.string :currency, null: false, default: "BRL", limit: 3

      t.timestamps
    end

    # Dedup de contas de uma mesma conexão (item Pluggy → N accounts).
    add_index :accounts, [ :bank_connection_id, :external_id ],
              unique: true, where: "external_id IS NOT NULL",
              name: "index_accounts_on_connection_and_external_id"
    add_check_constraint :accounts,
                         "kind IN ('checking', 'credit_card')",
                         name: "accounts_kind_check"
    add_check_constraint :accounts,
                         "institution IN ('nubank', 'inter', 'itau', 'santander', 'bb', 'manual')",
                         name: "accounts_institution_check"
  end
end
