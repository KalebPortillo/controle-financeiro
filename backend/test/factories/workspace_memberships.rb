FactoryBot.define do
  factory :workspace_membership do
    user
    workspace
    role      { "editor" }
    joined_at { Time.current }
  end
end
