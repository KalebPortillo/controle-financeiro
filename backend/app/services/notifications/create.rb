module Notifications
  # Único caminho de criação de notificação (RF17): persiste, broadcasta no
  # canal do workspace e (quando houver vínculo) despacha pro Telegram.
  # `dedup_key` torna a criação idempotente — colisão (unique index parcial)
  # vira no-op e retorna nil, sem broadcast.
  module Create
    module_function

    # `telegram: false` persiste + broadcasta in-app mas NÃO despacha pro
    # Telegram (usado quando o canal externo é tratado à parte — ex.: lote
    # pequeno de inbox que vai como mensagens individuais com botões).
    def call(workspace:, kind:, payload:, recipient_membership: nil, dedup_key: nil, telegram: true)
      notification = workspace.notifications.create!(
        kind:                 kind,
        payload:              payload,
        recipient_membership: recipient_membership,
        dedup_key:            dedup_key
      )

      NotificationsChannel.broadcast_to(workspace,
        event:        "notification_created",
        notification: Notifications::Serializer.call(notification))

      if telegram && workspace.telegram_chat_id.present?
        TelegramDeliveryJob.perform_later(notification.id)
      end

      notification
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
