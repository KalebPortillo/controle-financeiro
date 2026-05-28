FactoryBot.define do
  factory :tag do
    workspace
    sequence(:name) { |n| "tag-#{n}" }
  end
end
