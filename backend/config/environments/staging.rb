require "active_support/core_ext/integer/time"

# Staging — espelho de production com:
#   - hostname diferente (wallet-staging.portilho.cc, via APP_HOST)
#   - banco diferente (DATABASE_URL apontando pro Postgres staging)
#   - deprecações reportadas em log (em prod ficam silenciadas)
#
# Roda como container Kamal com RAILS_ENV=staging. Comportamento de runtime
# (eager_load, cache_store, log_to_stdout) é idêntico ao prod pra pegar bugs
# que só aparecem com classes lazy-loaded ou cache durável.
Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  config.active_storage.service = :local

  # Mesma postura SSL do production — ver explicação em production.rb.
  # (assume_ssl porque Cloudflare termina TLS, kamal-proxy fala HTTP com o app)
  config.assume_ssl = true
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log para STDOUT (containerized) com request_id.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"

  # Deprecações reportadas (em prod ficam silenciadas).
  config.active_support.report_deprecations = true

  config.cache_store = :solid_cache_store
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  config.action_mailer.default_url_options = { host: "wallet-staging.portilho.cc" }

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]

  config.hosts << ENV.fetch("APP_HOST", "wallet-staging.portilho.cc")
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
