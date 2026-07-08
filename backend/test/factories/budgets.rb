FactoryBot.define do
  factory :budget do
    workspace
    sequence(:name) { |n| "Orçamento #{n}" }
    kind { "tag" }
    monthly_limit_cents { 80_000 }
    alert_threshold_pct { 80 }
    enabled { true }
    target_tag { association :tag, workspace: workspace }

    trait :category do
      kind { "category" }
      target_tag { nil }
      target_category { association :category, workspace: workspace }
    end

    trait :composite do
      kind { "composite" }
      target_tag { nil }
    end
  end
end
