FactoryBot.define do
  factory :transaction do
    account
    workspace { account.workspace }

    direction            { "debit" }
    amount_cents         { 1234 }
    currency             { "BRL" }
    occurred_at          { Date.current }
    sequence(:original_description) { |n| "COMPRA ESTABELECIMENTO #{n}" }
    status               { "pending" }
    source               { "automatic_sync" }
    sequence(:source_metadata) { |n| { "id" => "pluggy-tx-#{n}" } }
  end
end
