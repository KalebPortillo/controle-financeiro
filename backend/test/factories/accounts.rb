FactoryBot.define do
  factory :account do
    workspace
    owner_membership do
      association(:workspace_membership, workspace: workspace)
    end
    sequence(:name) { |n| "Nubank CC ##{n}" }
    kind            { "checking" }
    institution     { "nubank" }
    sequence(:external_id) { |n| "pluggy-account-#{n}" }
    currency        { "BRL" }
  end
end
