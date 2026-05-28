ENV["RAILS_ENV"] ||= "test"

# Credenciais dummy de provider em test — webmock/VCR interceptam o HTTP,
# então os valores não importam, só precisam existir pros constructors
# (BankAggregators::Pluggy faz ENV.fetch). Se as reais estiverem no env
# (ex.: ao re-gravar cassettes com VCR_RECORD), elas têm precedência.
ENV["PLUGGY_CLIENT_ID"]      ||= "test-pluggy-client-id"
ENV["PLUGGY_CLIENT_SECRET"]  ||= "test-pluggy-client-secret"
ENV["PLUGGY_WEBHOOK_SECRET"] ||= "test-webhook-secret"

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "vcr"

# VCR — grava interações HTTP reais (uma vez) e replaya depois. Usamos
# pra testar adapters de provider externo (Pluggy, Gemini) sem dependência
# de rede em CI nem custar quota.
#
# Cassettes em test/vcr_cassettes/<provider>/<scenario>.yml.
# Re-gravar: REC=once bin/rails test test/... (ou ALL_RECORD_MODE=new_episodes).
VCR.configure do |c|
  c.cassette_library_dir = "test/vcr_cassettes"
  c.hook_into :webmock
  c.default_cassette_options = {
    record: ENV.fetch("VCR_RECORD", "none").to_sym,
    # method + uri é suficiente — incluir `body` exigiria que CI tivesse as
    # mesmas credenciais reais usadas no record (já que `filter_sensitive_data`
    # substitui o valor mas o matching ainda compara contra o ENV atual).
    match_requests_on: %i[method uri]
  }
  c.allow_http_connections_when_no_cassette = false

  # Filtra segredos do request/response antes de serializar pro disco.
  c.filter_sensitive_data("<PLUGGY_CLIENT_ID>")     { ENV["PLUGGY_CLIENT_ID"] }
  c.filter_sensitive_data("<PLUGGY_CLIENT_SECRET>") { ENV["PLUGGY_CLIENT_SECRET"] }

  # Mascara o apiKey JWT em todo lugar que ele aparece:
  #   - response body do /auth ({ "apiKey": "jwt..." })
  #   - request header X-API-KEY das chamadas autenticadas
  # JWTs sandbox expiram em ~2h, mas cassettes vão pro git — scrub é higiene.
  c.before_record do |interaction|
    body = interaction.response.body
    if body
      # apiKey (/auth) e accessToken (/connect_token) são JWTs — o accessToken
      # inclusive carrega o clientId em base64 no payload, então scrub total.
      body = body.gsub(/"apiKey"\s*:\s*"[^"]+"/,      '"apiKey":"<PLUGGY_API_KEY>"')
      body = body.gsub(/"accessToken"\s*:\s*"[^"]+"/, '"accessToken":"<PLUGGY_CONNECT_TOKEN>"')
      interaction.response.body = body
    end
    %w[X-API-KEY X-Api-Key].each do |h|
      interaction.request.headers[h] = [ "<PLUGGY_API_KEY>" ] if interaction.request.headers&.key?(h)
    end
  end
end

# OmniAuth em modo de teste — preenchemos `OmniAuth.config.mock_auth[:google_oauth2]`
# por teste (no helper sign_in_as ou direto). Sem isso, qualquer chamada de
# auth tentaria bater no Google real.
OmniAuth.config.test_mode = true
OmniAuth.config.silence_get_warning = true

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # factory_bot syntax direto: `build(:user)` em vez de `FactoryBot.build(:user)`.
    include FactoryBot::Syntax::Methods
  end
end

# Rack::Attack desligado por default em test — testes de auth_flow/etc hit
# /api/v1/auth/* várias vezes e consumiam o counter, fazendo o teste de
# rate-limit falhar dependendo da ordem de execução. O teste específico
# do Rack::Attack re-habilita no `setup`.
Rack::Attack.enabled = false

module ActionDispatch
  class IntegrationTest
    # Reseta o mock entre testes pra não vazar estado.
    setup do
      OmniAuth.config.mock_auth[:google_oauth2] = nil
    end

    # Simula o callback OAuth do Google e segue até a sessão ficar gravada.
    def sign_in_as(user)
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: user.google_uid,
        info: {
          email: user.email,
          name:  user.name,
          image: user.avatar_url
        }
      )
      get "/api/v1/auth/google_oauth2/callback"
    end
  end
end
