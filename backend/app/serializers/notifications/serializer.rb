module Notifications
  # Schema canônico de uma notificação no JSON da API (RF17). Compartilhado
  # entre o controller (REST) e o broadcast do Action Cable.
  class Serializer
    def self.call(notification)
      {
        id:         notification.id,
        kind:       notification.kind,
        payload:    notification.payload,
        read_at:    notification.read_at&.iso8601,
        created_at: notification.created_at.iso8601
      }
    end
  end
end
