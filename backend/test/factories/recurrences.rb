FactoryBot.define do
  factory :recurrence do
    workspace
    account { association(:account, workspace: workspace) }
    sequence(:descriptor_pattern) { |n| "NETFLIX #{n}" }
    expected_amount_cents { 5990 }
    cadence { "monthly" }
    status  { "active" }
    source  { "manual" }
  end
end
