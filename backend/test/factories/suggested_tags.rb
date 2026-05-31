FactoryBot.define do
  factory :suggested_tag do
    association :workspace
    sequence(:name) { |n| "Sugestão #{n}" }
    rationale { "8 transações em mercados" }
    coverage { 8 }
    source { "detected" }
    status { "pending" }
  end
end
