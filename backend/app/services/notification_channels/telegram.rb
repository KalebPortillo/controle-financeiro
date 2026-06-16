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
    # `reply_markup` (opcional) anexa um inline keyboard (botões de ação).
    def send_message(chat_id:, text:, reply_markup: nil)
      payload = { chat_id: chat_id, text: text }
      payload[:reply_markup] = reply_markup if reply_markup
      request("sendMessage", payload)
    end

    # Responde o toque num botão inline — tira o "loading" do botão e, com
    # `text`, mostra um toast curto pro usuário.
    def answer_callback_query(callback_query_id:, text: nil)
      payload = { callback_query_id: callback_query_id }
      payload[:text] = text if text
      request("answerCallbackQuery", payload)
    end

    # Edita uma mensagem já enviada (usado pós-ação: troca o texto e remove os
    # botões passando reply_markup vazio, ou nenhum).
    def edit_message_text(chat_id:, message_id:, text:, reply_markup: nil)
      payload = { chat_id: chat_id, message_id: message_id, text: text }
      payload[:reply_markup] = reply_markup if reply_markup
      request("editMessageText", payload)
    end

    # Registra o webhook de updates (rake telegram:set_webhook). secret_token
    # volta em cada update no header X-Telegram-Bot-Api-Secret-Token.
    def set_webhook(url:, secret_token:)
      request("setWebhook", url: url, secret_token: secret_token,
                            allowed_updates: [ "message", "callback_query" ])
    end

    # Lista de comandos do bot (aparece no menu "/" do Telegram).
    # commands: [{ command: "pendentes", description: "..." }, ...].
    def set_my_commands(commands:)
      request("setMyCommands", commands: commands)
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
