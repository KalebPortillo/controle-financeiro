FactoryBot.define do
  factory :import do
    association :workspace
    association :uploaded_by_membership, factory: :workspace_membership
    sequence(:filename) { |n| "extrato-#{n}.csv" }
    format { "csv" }
    file_size_bytes { 1_024 }
    status { "pending" }
  end
end
