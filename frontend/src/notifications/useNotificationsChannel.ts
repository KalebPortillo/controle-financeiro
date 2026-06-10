import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { getCableConsumer } from '../api/cable'
import {
  notificationsKey,
  type AppNotification,
  type NotificationsPayload,
} from './useNotifications'

type NotificationCreatedMessage = {
  event: string
  notification: AppNotification
}

/**
 * Assina o NotificationsChannel (RF17) e faz prepend de cada
 * `notification_created` no cache — o sininho atualiza em tempo real, sem
 * polling. inbox_new também invalida a inbox (chegaram gastos novos).
 */
export function useNotificationsChannel(workspaceId: string | null | undefined) {
  const qc = useQueryClient()

  useEffect(() => {
    if (!workspaceId) return

    const subscription = getCableConsumer().subscriptions.create(
      { channel: 'NotificationsChannel', workspace_id: workspaceId },
      {
        received(data: NotificationCreatedMessage) {
          if (data?.event !== 'notification_created') return
          qc.setQueryData<NotificationsPayload>(notificationsKey, (prev) => {
            if (!prev) return prev
            if (prev.notifications.some((n) => n.id === data.notification.id)) return prev
            return {
              notifications: [data.notification, ...prev.notifications],
              unread_count: prev.unread_count + 1,
            }
          })
          if (data.notification.kind === 'inbox_new') {
            qc.invalidateQueries({ queryKey: ['transactions', 'pending'] })
          }
        },
      }
    )

    return () => {
      subscription.unsubscribe()
    }
  }, [workspaceId, qc])
}
