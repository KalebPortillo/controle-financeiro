module Notifications
  # Entrega uma notificação já persistida no grupo do Telegram do workspace.
  # Best-effort: o in-app nunca depende disso. 429 re-tenta espaçado; 4xx
  # (chat sumiu, bot removido) descarta — o vínculo quebrado aparece pro
  # usuário na tela de config, não como retry infinito.
  class TelegramDeliveryJob < ApplicationJob
    queue_as :default

    retry_on NotificationChannels::RateLimitError, wait: 30.seconds, attempts: 3
    discard_on NotificationChannels::ApiError
    discard_on ActiveRecord::RecordNotFound

    def perform(notification_id, channel: NotificationChannels::Telegram.new)
      notification = Notification.find(notification_id)
      chat_id      = notification.workspace.telegram_chat_id
      return if chat_id.blank? # desvinculou entre enqueue e perform

      channel.send_message(chat_id: chat_id, text: TelegramMessage.call(notification))
    end
  end
end
