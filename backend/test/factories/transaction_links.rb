FactoryBot.define do
  factory :transaction_link do
    transient do
      workspace_obj { association(:workspace) }
    end

    workspace { workspace_obj }
    primary_transaction { association(:transaction, workspace: workspace_obj, account: association(:account, workspace: workspace_obj)) }
    related_transaction { association(:transaction, workspace: workspace_obj, account: association(:account, workspace: workspace_obj)) }
    relation_type { "iof" }
    origin { "automatic" }
    confidence { 0.99 }
  end
end
