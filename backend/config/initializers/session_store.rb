# Session cookie hardening — defesa em profundidade.
#
# Defaults do Rails 8 já são razoáveis:
#   - cookie store (signed, encrypted via master.key)
#   - httponly: true (JS não enxerga)
#
# Aqui declaramos explicitamente o que importa para auditoria + ajustamos
# same_site pra `:lax` (default). `secure: true` é setado automaticamente
# em prod/staging porque `config.force_ssl = true`.
#
# Quando RF16 (auth) entrar:
#   - Avaliar trocar pra :strict (mais seguro, mas quebra login via link de email).
#   - Adicionar key rotation se necessário.
Rails.application.config.session_store :cookie_store,
  key: "_controle_financeiro_session",
  same_site: :lax,
  httponly: true
