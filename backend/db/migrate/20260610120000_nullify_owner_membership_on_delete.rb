class NullifyOwnerMembershipOnDelete < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :bank_connections, column: :owner_membership_id
    remove_foreign_key :accounts,         column: :owner_membership_id

    change_column_null :bank_connections, :owner_membership_id, true
    change_column_null :accounts,         :owner_membership_id, true

    add_foreign_key :bank_connections, :workspace_memberships,
                    column: :owner_membership_id, on_delete: :nullify
    add_foreign_key :accounts, :workspace_memberships,
                    column: :owner_membership_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :bank_connections, column: :owner_membership_id
    remove_foreign_key :accounts,         column: :owner_membership_id

    change_column_null :bank_connections, :owner_membership_id, false
    change_column_null :accounts,         :owner_membership_id, false

    add_foreign_key :bank_connections, :workspace_memberships, column: :owner_membership_id
    add_foreign_key :accounts,         :workspace_memberships, column: :owner_membership_id
  end
end
