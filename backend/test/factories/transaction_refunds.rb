FactoryBot.define do
  factory :transaction_refund do
    association :refund_transaction, factory: :transaction
    association :refunded_transaction, factory: :transaction
    association :confirmed_by_membership, factory: :workspace_membership
    confirmed_at { Time.current }
  end
end
