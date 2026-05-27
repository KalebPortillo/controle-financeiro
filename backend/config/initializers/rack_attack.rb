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
