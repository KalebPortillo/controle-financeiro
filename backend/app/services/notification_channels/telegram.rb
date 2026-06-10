require "net/http"
require "uri"
require "json"

module NotificationChannels
  # Cliente HTTP minimal para a Bot API do Telegram (mesmo molde de
  # BankAggregators::Pluggy). O bot token vai no PATH da URL — cuidado com
  # logs e cassettes (filter_sensitive_data no test_helper).
  #
  # Não responsável: escolher chat, montar texto, retry. Isso vive em camadas
  # acima (TelegramDeliveryJob, TelegramMessage).
  class Telegram
    BASE_HOST   = "api.telegram.org".freeze
    USER_AGENT  = "controle-financeiro/1.0".freeze
    TIMEOUT_SEC = 15

    def initialize(bot_token: ENV.fetch("TELEGRAM_BOT_TOKEN"))
      @bot_token = bot_token
    end

    # Envia texto puro (sem parse_mode — nada de Markdown/HTML escapando errado).
    def send_message(chat_id:, text:)
      request("sendMessage", chat_id: chat_id, text: text)
    end

    # Registra o webhook de updates (rake telegram:set_webhook). secret_token
    # volta em cada update no header X-Telegram-Bot-Api-Secret-Token.
    def set_webhook(url:, secret_token:)
      request("setWebhook", url: url, secret_token: secret_token,
                            allowed_updates: [ "message" ])
    end

    private

    def request(method, payload)
      uri = URI("https://#{BASE_HOST}/bot#{@bot_token}/#{method}")
      req = Net::HTTP::Post.new(uri)
      req["Accept"]       = "application/json"
      req["User-Agent"]   = USER_AGENT
      req["Content-Type"] = "application/json"
      req.body            = payload.to_json

      response = http.request(req)
      body     = parse_body(response.body)

      case response.code.to_i
      when 200..299
        body
      when 429
        raise RateLimitError.new(
          "Telegram rate limited: #{body['description']}",
          retry_after: body.dig("parameters", "retry_after")
        )
      when 400..499
        raise ApiError, "Telegram refused request: HTTP #{response.code} — #{body['description']}"
      else
        raise Error, "Telegram HTTP #{response.code}: #{response.body.to_s[0, 200]}"
      end
    end

    def parse_body(raw)
      raw.to_s.empty? ? {} : JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end

    def http
      @http ||= Net::HTTP.new(BASE_HOST, 443).tap do |h|
        h.use_ssl      = true
        h.open_timeout = TIMEOUT_SEC
        h.read_timeout = TIMEOUT_SEC
      end
    end
  end
end
