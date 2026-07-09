FactoryBot.define do
  factory :recurrence_exclusion do
    transient do
      workspace_obj { association(:workspace) }
    end

    workspace { workspace_obj }
    recurrence { association(:recurrence, workspace: workspace_obj) }
    excluded_transaction { association(:transaction, workspace: workspace_obj, account: recurrence.account) }
  end
end
