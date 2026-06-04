FactoryBot.define do
  factory :suggested_category do
    association :workspace
    sequence(:name) { |n| "Categoria #{n}" }
    tag_names { [ "Mercado" ] }
    status { "pending" }
  end
end
