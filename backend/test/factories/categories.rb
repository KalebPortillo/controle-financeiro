FactoryBot.define do
  factory :category do
    workspace
    sequence(:name) { |n| "categoria-#{n}" }
  end
end
