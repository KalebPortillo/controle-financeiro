FactoryBot.define do
  factory :internal_transfer do
    association :workspace
    association :debit_transaction, factory: :transaction, direction: "debit"
    association :credit_transaction, factory: :transaction, direction: "credit"
    detected_at { Time.current }
  end
end
