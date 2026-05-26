require "active_support/core_ext/integer/time"

# Staging — mirror de development com DB separado e hostnames públicos.
# Quando o app entrar em deploy real (Kamal), staging.rb deve convergir para
# um espelho de production (eager_load, cache, etc.) com flag para debug fácil.
Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  config.action_controller.perform_caching = false
  config.cache_store = :memory_store

  config.active_storage.service = :local

  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: "wallet-staging.portilho.cc" }

  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_record.query_log_tags_enabled = true
  config.active_job.verbose_enqueue_logs = true
  config.action_dispatch.verbose_redirect_logs = true
  config.action_view.annotate_rendered_view_with_filenames = true
  config.action_controller.raise_on_missing_callback_actions = true

  # Host público de staging via Cloudflare Tunnel.
  config.hosts << "wallet-staging.portilho.cc"
end
