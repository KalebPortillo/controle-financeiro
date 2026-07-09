FactoryBot.define do
  factory :transaction_refund do
    association :refund_transaction, factory: :transaction
    association :refunded_transaction, factory: :transaction
    association :confirmed_by_membership, factory: :workspace_membership
    confirmed_at { Time.current }
    origin { "manual" }

    # RF10.6 — vínculo automático (match de código): sem membership.
    trait :automatic do
      origin { "automatic" }
      confirmed_by_membership { nil }
    end
  end
end
