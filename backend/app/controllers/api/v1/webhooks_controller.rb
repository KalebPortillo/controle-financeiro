class Api::V1::WebhooksController < ApplicationController
  # Pluggy e Telegram chamam essas rotas (máquina→máquina), não um usuário
  # logado. NÃO exigem sessão; validam um header secreto compartilhado
  # (Pluggy: header configurável no registro + IP whitelist 177.71.238.212;
  # Telegram: secret_token do setWebhook ecoado em cada update).
  skip_before_action :verify_authenticity_token, raise: false
  before_action :verify_webhook_secret, only: [ :pluggy ]
  before_action :verify_telegram_secret, only: [ :telegram ]

  # Eventos que disparam um sync (transações novas/atualizadas).
  SYNC_EVENTS  = %w[item/updated transactions/created transactions/updated].freeze
  ERROR_EVENTS = %w[item/error item/login_error].freeze

  # POST /api/v1/webhooks/pluggy
  def pluggy
    event   = params[:event].to_s
    item_id = params[:itemId].to_s
    connection = BankConnection.find_by(provider: "pluggy", external_connection_id: item_id)

    # Item desconhecido ou evento irrelevante → 200 (ack) sem efeito. Pluggy
    # reenviaria em não-2xx; não queremos retries por evento que ignoramos.
    if connection
      if SYNC_EVENTS.include?(event)
        connection.update!(status: "syncing")
        BankConnections::SyncJob.perform_later(connection.id)
      elsif ERROR_EVENTS.include?(event)
        connection.update!(status: "error", error_message: params.dig(:error, :message))
      end
    end

    head :ok
  end

  # POST /api/v1/webhooks/telegram — updates do bot (RF17). Só nos importa
  # "/start <code>" (ou "/start@bot <code>", como chega em grupo) pra vincular
  # o chat ao workspace. Sempre 200: Telegram re-envia updates em não-2xx e
  # não queremos retry de mensagem que ignoramos de propósito.
  START_COMMAND = %r{\A/start(?:@\w+)?\s+(\S+)}

  def telegram
    text  = params.dig(:message, :text).to_s
    chat  = params.dig(:message, :chat)

    if chat.present? && (match = START_COMMAND.match(text))
      Notifications::LinkTelegramChat.call(
        code:       match[1],
        chat_id:    chat[:id],
        chat_title: chat[:title]
      )
    end

    head :ok
  end

  private

  def verify_telegram_secret
    expected = ENV["TELEGRAM_WEBHOOK_SECRET"].to_s
    given    = request.headers["X-Telegram-Bot-Api-Secret-Token"].to_s
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

    head :unauthorized
  end

  def verify_webhook_secret
    expected = ENV["PLUGGY_WEBHOOK_SECRET"].to_s
    given    = request.headers["X-Webhook-Secret"].to_s
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

    head :unauthorized
  end
end
