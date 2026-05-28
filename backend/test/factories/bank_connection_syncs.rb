FactoryBot.define do
  factory :bank_connection_sync do
    bank_connection
    started_at       { 1.minute.ago }
    finished_at      { Time.current }
    duration_seconds { 12 }
    status           { "success" }
    created_count    { 3 }
    duplicate_count  { 1 }
    error_count      { 0 }
  end
end
