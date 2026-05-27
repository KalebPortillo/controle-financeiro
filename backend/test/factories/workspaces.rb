FactoryBot.define do
  factory :workspace do
    sequence(:name) { |n| "Workspace #{n}" }
    association :created_by_user, factory: :user
  end
end
