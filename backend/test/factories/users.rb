FactoryBot.define do
  factory :user do
    sequence(:email)      { |n| "user#{n}@example.com" }
    sequence(:google_uid) { |n| "google-uid-#{n}" }
    sequence(:name)       { |n| "User #{n}" }
    avatar_url            { "https://lh3.googleusercontent.com/a/default-user" }
  end
end
