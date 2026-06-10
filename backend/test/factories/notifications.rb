FactoryBot.define do
  factory :notification do
    workspace
    kind    { "sync_failed" }
    payload { { "institution_label" => "Nubank", "error_message" => "Credenciais expiradas" } }
  end
end
