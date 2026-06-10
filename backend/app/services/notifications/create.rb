module Notifications
  # Único caminho de criação de notificação (RF17): persiste, broadcasta no
  # canal do workspace e (quando houver vínculo) despacha pro Telegram.
  # `dedup_key` torna a criação idempotente — colisão (unique index parcial)
  # vira no-op e retorna nil, sem broadcast.
  module Create
    module_function

    def call(workspace:, kind:, payload:, recipient_membership: nil, dedup_key: nil)
      notification = workspace.notifications.create!(
        kind:                 kind,
        payload:              payload,
        recipient_membership: recipient_membership,
        dedup_key:            dedup_key
      )

      NotificationsChannel.broadcast_to(workspace,
        event:        "notification_created",
        notification: Notifications::Serializer.call(notification))

      notification
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
