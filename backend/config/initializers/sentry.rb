# Sentry — error tracking + performance.
# DSN vem de ENV["SENTRY_DSN"]. Sem DSN, o SDK fica inerte (não envia nada).
return if ENV["SENTRY_DSN"].blank?

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = Rails.env

  # Captura exceções e breadcrumbs do Rails (controllers, jobs, etc).
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]

  # Performance: amostra 10% das transações em todos os envs.
  # Subir em prod conforme volume permitir.
  config.traces_sample_rate = 0.1

  # PII off por default — usuários têm dados financeiros sensíveis.
  config.send_default_pii = false

  # Ignora tipos de erro ruidosos / não-acionáveis.
  config.excluded_exceptions += [
    "ActionController::RoutingError",
    "ActiveRecord::RecordNotFound"
  ]
end
