class Api::V1::WebhooksController < ApplicationController
  # Pluggy chama essa rota (máquina→máquina), não um usuário logado.
  # NÃO exige sessão; valida um header secreto compartilhado em vez disso
  # (Pluggy não assina com HMAC — segurança via header configurável no
  # registro do webhook + IP whitelist 177.71.238.212).
  skip_before_action :verify_authenticity_token, raise: false
  before_action :verify_webhook_secret

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

  private

  def verify_webhook_secret
    expected = ENV["PLUGGY_WEBHOOK_SECRET"].to_s
    given    = request.headers["X-Webhook-Secret"].to_s
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

    head :unauthorized
  end
end
