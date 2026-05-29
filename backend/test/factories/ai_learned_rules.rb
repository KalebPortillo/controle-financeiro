FactoryBot.define do
  factory :ai_learned_rule do
    workspace
    sequence(:descriptor_pattern) { |n| "estabelecimento-#{n}" }
    improved_title { "Título Aprendido" }
    tag_ids { [] }
    match_count { 1 }
    last_seen_at { Time.current }
  end
end
