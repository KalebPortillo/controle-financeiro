# Rack::Attack — rate-limiting baseline + proteção contra abuso nos endpoints
# de auth (callback OAuth do Google em particular).
#
# Storage: Rails.cache. Em test fica memory_store por env; em prod/staging
# vai pro solid_cache (banco). Não há Redis na stack.

class Rack::Attack
  ### Cache backend ###
  # Em test, Rails.cache é :null_store (incrementos viram no-op) — daria
  # falso positivo "throttle nunca dispara". Em prod/staging usamos
  # Rails.cache (solid_cache), que tem persistência cross-instância.
  Rack::Attack.cache.store = if Rails.env.test?
    ActiveSupport::Cache::MemoryStore.new
  else
    Rails.cache
  end

  ### Allowlists ###

  # Healthcheck do kamal-proxy precisa passar sempre, independente do IP.
  # Sem isso, um burst do load-balancer marcaria o app como unhealthy.
  Rack::Attack.safelist("allow /up") do |req|
    req.path == "/up"
  end

  ### Throttles ###

  # Endpoints de auth — limite por IP. Cobre tanto a fase de request
  # (/api/v1/auth/google_oauth2) quanto de callback. 10 reqs/min é
  # generoso para o uso real (clicar "Entrar com Google" → bater no Google
  # → voltar no callback = 2 hits) mas atalha brute-force.
  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/v1/auth/")
  end

  # Reanálise de IA — queima quota Gemini (RF3.5). 5/min por IP é o suficiente
  # para casos de uso reais; bloqueia loop acidental no frontend.
  throttle("ai_reanalyze/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/api/v1/transactions/reanalyze" && req.post?
  end

  # Connect token / sync no Pluggy — cada chamada gera tokens ou puxa pull
  # remoto. 10/min é maior que qualquer uso humano e absorve double-clicks.
  throttle("pluggy_write/ip", limit: 10, period: 1.minute) do |req|
    next unless req.post?
    path = req.path
    if path == "/api/v1/bank_connections/connect_token" ||
       path == "/api/v1/bank_connections/sync_all" ||
       path =~ %r{\A/api/v1/bank_connections/[^/]+/(sync|reconnect)\z}
      req.ip
    end
  end

  ### Response ###

  # Quando bate o teto, devolve 429 com payload padrão da API.
  self.throttled_responder = lambda do |request|
    match_data  = request.env["rack.attack.match_data"] || {}
    retry_after = (match_data[:period] || 60).to_s

    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after
      },
      [ { error: { code: "rate_limited", message: "Too many requests. Try again soon." } }.to_json ]
    ]
  end
end
