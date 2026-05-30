class AddOnboardingStateToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :onboarding_state, :jsonb,
               default: { status: "not_started" }, null: false

    add_index :workspaces,
              "(onboarding_state ->> 'status')",
              name: "index_workspaces_on_onboarding_status"
  end
end
