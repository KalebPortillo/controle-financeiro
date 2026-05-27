class CreateWorkspaceMemberships < ActiveRecord::Migration[8.1]
  def change
    # `role` é enum no nível do app (Rails enum). No DB fica como string
    # com CHECK constraint — simples de evoluir sem migration de tipo nativo.
    create_table :workspace_memberships, id: :uuid do |t|
      t.references :user,      type: :uuid, null: false, foreign_key: true
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string     :role,      null: false, default: "editor"
      t.datetime   :joined_at, null: false

      t.timestamps
    end

    add_index :workspace_memberships, [ :user_id, :workspace_id ], unique: true
    add_check_constraint :workspace_memberships,
                         "role IN ('editor', 'viewer')",
                         name: "workspace_memberships_role_check"
  end
end
