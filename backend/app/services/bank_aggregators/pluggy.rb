require "net/http"
require "uri"
require "json"

module BankAggregators
  # Cliente HTTP minimal para a API do Pluggy (https://api.pluggy.ai).
  #
  # Responsabilidades:
  #   - trocar (client_id, client_secret) por apiKey via POST /auth e cachear
  #     em memória pelo lifetime da instância
  #   - chamar endpoints autenticados com header `X-API-KEY`
  #   - em 401, fazer refresh do apiKey + retry uma única vez
  #
  # Não responsável: persistência, mapeamento pra ActiveRecord, agendamento
  # de sync. Isso vive em camadas acima (jobs, services específicos).
  class Pluggy
    BASE_URL    = "https://api.pluggy.ai".freeze
    USER_AGENT  = "controle-financeiro/1.0".freeze
    TIMEOUT_SEC = 15

    # Connector IDs estáticos no Pluggy. Não chamamos /connectors em runtime —
    # o widget Pluggy Connect cuida da escolha; só precisamos referenciar nos
    # nossos fluxos (sandbox em dev/test, Nubank em prod).
    CONNECTORS = {
      sandbox_basic: 2,
      nubank:        612
    }.freeze

    def initialize(client_id:, client_secret:)
      @client_id     = client_id
      @client_secret = client_secret
    end

    # JWT que autentica subsequentes requests. Cacheado depois da primeira chamada.
    def api_key
      @api_key ||= authenticate!
    end

    # Token curto-prazo que o widget Pluggy Connect (frontend) usa pra abrir
    # o fluxo de conexão. `options` aceita ex.: { itemId: ... } pra reconectar.
    def create_connect_token(options = {})
      payload = request(Net::HTTP::Post, "/connect_token",
                        body: options, authenticated: true, retry_on_401: true)
      payload.fetch("accessToken")
    end

    # Detalhes de um item (conexão). { id:, connector_id:, connector_name:, status: }.
    def get_item(item_id:)
      payload = get("/items/#{item_id}")
      connector = payload["connector"] || {}
      {
        id:             payload.fetch("id"),
        connector_id:   connector["id"],
        connector_name: connector["name"],
        status:         payload["status"]
      }
    end

    # Lista accounts de um item (item = conexão Pluggy com banco).
    # Cada item: { id:, type:, name:, number?:, balance?:, currency_code? }.
    def list_accounts(item_id:)
      payload = get("/accounts", { itemId: item_id })
      payload.fetch("results").map { |a| account_view(a) }
    end

    # Lista transações de uma account a partir de uma data.
    # Cada item: { id:, amount:, currency_code:, date:, description:, raw: }.
    def list_transactions(account_id:, from:, to: nil)
      params = { accountId: account_id, from: from.to_s }
      params[:to] = to.to_s if to
      payload = get("/transactions", params)
      payload.fetch("results").map { |t| transaction_view(t) }
    end

    # Webhooks registrados na conta Pluggy. [{ id:, event:, url: }, ...].
    def list_webhooks
      payload = get("/webhooks")
      payload.fetch("results", []).map { |w| { id: w["id"], event: w["event"], url: w["url"] } }
    end

    # Registra um webhook (UM evento por webhook, conforme a API do Pluggy).
    # `headers` é um objeto que o Pluggy REENVIA em toda notificação — usamos
    # pra ecoar o X-Webhook-Secret que o nosso endpoint valida (Pluggy não
    # assina HMAC). Devolve { id:, event:, url: }.
    def create_webhook(url:, event:, headers: {})
      payload = request(Net::HTTP::Post, "/webhooks",
                        body: { url: url, event: event, headers: headers },
                        authenticated: true, retry_on_401: true)
      { id: payload["id"], event: payload["event"], url: payload["url"] }
    end

    private

    def authenticate!
      res = post("/auth", { clientId: @client_id, clientSecret: @client_secret })
      res.fetch("apiKey")
    end

    def get(path, query = {})
      request(Net::HTTP::Get, path, query: query, authenticated: true, retry_on_401: true)
    end

    def post(path, body)
      request(Net::HTTP::Post, path, body: body, authenticated: false)
    end

    def request(klass, path, query: {}, body: nil, authenticated:, retry_on_401: false)
      uri = URI.join(BASE_URL, path)
      uri.query = URI.encode_www_form(query) if query.any?

      req = klass.new(uri)
      req["Accept"]       = "application/json"
      req["User-Agent"]   = USER_AGENT
      req["X-API-KEY"]    = api_key if authenticated
      if body
        req["Content-Type"] = "application/json"
        req.body            = body.to_json
      end

      response = http.request(req)

      case response.code.to_i
      when 200..299
        response.body.empty? ? {} : JSON.parse(response.body)
      when 401
        if authenticated && retry_on_401
          @api_key = nil
          request(klass, path, query: query, body: body, authenticated: true, retry_on_401: false)
        else
          raise AuthenticationError, "Pluggy rejected credentials (HTTP 401)"
        end
      when 400, 403, 404, 422
        raise ItemError, "Pluggy refused request: HTTP #{response.code} — #{response.body[0, 200]}"
      else
        raise UpstreamError.new(status: response.code, body: response.body)
      end
    end

    def http
      @http ||= Net::HTTP.new("api.pluggy.ai", 443).tap do |h|
        h.use_ssl       = true
        h.open_timeout  = TIMEOUT_SEC
        h.read_timeout  = TIMEOUT_SEC
      end
    end

    def account_view(a)
      {
        id:            a.fetch("id"),
        type:          a["type"],
        name:          a["name"] || a["marketingName"],
        number:        a["number"],
        brand:         a.dig("creditData", "brand"), # bandeira do cartão (MASTERCARD…)
        balance:       a["balance"],
        currency_code: a["currencyCode"]
      }
    end

    def transaction_view(t)
      {
        id:            t.fetch("id"),
        amount:        t.fetch("amount"),
        # "DEBIT"/"CREDIT" — fonte confiável da direção. Em cartão de crédito o
        # sinal do amount é invertido (gasto vem positivo), então não dá pra
        # inferir débito/crédito só pelo sinal. Ver BankConnections::Sync.
        type:          t["type"],
        currency_code: t["currencyCode"],
        # Valor já convertido pra moeda da CONTA (ex.: compra em USD → BRL). O
        # Pluggy manda null quando a compra é na própria moeda da conta. Sem
        # isso, gasto em dólar entraria com o número em USD como se fosse BRL.
        amount_in_account_currency: t["amountInAccountCurrency"],
        date:          t["date"],
        description:   t["description"] || t["descriptionRaw"],
        raw:           t
      }
    end
  end
end
