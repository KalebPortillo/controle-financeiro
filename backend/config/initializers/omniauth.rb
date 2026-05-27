# OmniAuth — Google OAuth2 (OIDC).
#
# Em test/development o `client_id`/`client_secret` podem ficar vazios — o modo
# de teste do OmniAuth (test_mode = true em test_helper.rb) bypassa o handshake
# real. Em staging/production, ENV é obrigatório e populado pelo Kamal.
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           ENV["GOOGLE_OAUTH_CLIENT_ID"],
           ENV["GOOGLE_OAUTH_CLIENT_SECRET"],
           {
             scope: "email,profile",
             prompt: "select_account",
             # Não queremos o token de acesso pro usuário; só identidade.
             skip_jwt: true,
             # OmniAuth 2.x exige POST no callback por default. Como o request
             # vem do redirect do Google (GET), liberamos GET nessa rota.
             # A proteção contra CSRF no callback OAuth é feita via state
             # param (default do strategy).
             provider_ignores_state: false
           }
end

# O OmniAuth monta o request-phase e o callback-phase em URLs no formato
# `<path_prefix>/<provider>` e `<path_prefix>/<provider>/callback`. Como o
# frontend bate em /api/v1, montamos ali também — assim Cloudflare/CDN podem
# tratar tudo abaixo de /api/v1 como API.
OmniAuth.config.path_prefix = "/api/v1/auth"

# Sem POST do botão "Sign in with Google" (chamamos /api/v1/auth/google_oauth2
# direto via <a href>); então não precisamos do CSRF token de form.
OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true

# Logger do OmniAuth vai pro Rails.logger, com tags de request.
OmniAuth.config.logger = Rails.logger

# Falhas (invalid_credentials, csrf, etc.) redirecionam pra /api/v1/auth/failure.
OmniAuth.config.on_failure = proc do |env|
  Api::V1::SessionsController.action(:failure).call(env)
end
