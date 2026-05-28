FactoryBot.define do
  factory :bank_connection do
    workspace
    owner_membership do
      association(:workspace_membership, workspace: workspace)
    end
    provider               { "pluggy" }
    sequence(:external_connection_id) { |n| "pluggy-item-#{n}" }
    status                 { "connected" }
    sync_history_since     { Date.new(Time.current.year, 1, 1) }
  end
end
