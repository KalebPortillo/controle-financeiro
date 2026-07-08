require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Sessão via cookie + cookies signed/encrypted são necessários pra
    # OmniAuth (state param + sessão pós-login). API mode não inclui
    # esse middleware por padrão — adicionamos manualmente.
    #
    # ATENÇÃO: em api_only o `config.session_store` (initializer) é INERTE — este
    # `use` manual é o middleware REAL, então TODA opção de cookie mora aqui.
    # `expire_after` torna o cookie persistente com validade ROLANTE: sem ele o
    # iOS/PWA trata como cookie de sessão de browser e o descarta ao fechar o
    # app — o usuário reloga "toda hora". Ver config/initializers/session_store.rb.
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
                          key: "_controle_financeiro_session",
                          same_site: :lax,
                          httponly: true,
                          expire_after: 30.days
  end
end
