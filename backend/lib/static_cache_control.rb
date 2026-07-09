# frozen_string_literal: true

# Corrige o cache do shell do SPA. `config.public_file_server.headers` aplica
# `max-age=1 ano` em TODO arquivo de public/ — ótimo para os assets hasheados
# (/assets/index-ABC123.js: conteúdo muda ⇒ nome muda), mas fatal para o shell:
# com index.html e sw.js cacheados por 1 ano, o navegador nunca rebusca a página
# nem atualiza o Service Worker, prendendo o usuário numa versão antiga do app.
#
# Este middleware roda por FORA do ActionDispatch::Static (insert_before) e, na
# volta, sobrescreve o Cache-Control do shell para `no-cache` (o navegador pode
# guardar, mas precisa revalidar com o servidor antes de usar). Assets hasheados
# seguem imutáveis.
class StaticCacheControl
  REVALIDATE = %w[/ /index.html /sw.js /manifest.webmanifest].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    path = env["PATH_INFO"].to_s
    headers["cache-control"] = "no-cache" if REVALIDATE.include?(path) || path.end_with?(".html")
    [ status, headers, body ]
  end
end
