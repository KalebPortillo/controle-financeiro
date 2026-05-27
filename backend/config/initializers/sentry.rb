# Sentry — error tracking + performance.
# DSN vem de ENV["SENTRY_DSN"]. Sem DSN, o SDK fica inerte (não envia nada).
return if ENV["SENTRY_DSN"].blank?

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = Rails.env

  # Captura exceções e breadcrumbs do Rails (controllers, jobs, etc).
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]

  # Performance: desativado pré-MVP (sem usuários reais, traces consomem
  # quota sem valor). Subir para 0.1 em prod quando RF16+ estiver em uso.
  config.traces_sample_rate = 0.0

  # PII off por default — usuários têm dados financeiros sensíveis.
  config.send_default_pii = false

  # Ignora tipos de erro ruidosos / não-acionáveis.
  config.excluded_exceptions += [
    "ActionController::RoutingError",
    "ActiveRecord::RecordNotFound"
  ]

  # Hook para sanitizar dados antes de enviar pro Sentry. Hoje não temos
  # nada sensível para escapar (a API ainda não recebe transações reais),
  # mas o hook fica aqui — quando RF1 (Pluggy) ou RF12 (entrada manual)
  # começarem a popular params/exception_message com amount_cents,
  # description, etc, basta strip-ar dentro do bloco.
  config.before_send = ->(event, _hint) do
    # TODO(RF1/RF12): sanitizar amount_cents, description, account info
    # de event.request, event.extra, event.exception.values quando essas
    # rotas existirem.
    event
  end
end
