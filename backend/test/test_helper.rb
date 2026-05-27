ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

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
