import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

export type NotificationKind =
  | 'inbox_new'
  | 'budget_warning'
  | 'budget_exceeded'
  | 'recurrent_missed'
  | 'sync_failed'
  | 'import_completed'

export type AppNotification = {
  id: string
  kind: NotificationKind
  payload: Record<string, unknown>
  read_at: string | null
  created_at: string
}

export type NotificationsPayload = {
  notifications: AppNotification[]
  unread_count: number
}

export const notificationsKey = ['notifications'] as const

// Lista as notificações do workspace (RF17) + contador pro badge do sininho.
export function useNotifications() {
  return useQuery({
    queryKey: notificationsKey,
    queryFn: () => apiFetch<NotificationsPayload>('/api/v1/notifications'),
  })
}

export function useMarkRead() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) =>
      apiFetch(`/api/v1/notifications/${id}/mark_read`, { method: 'POST' }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: notificationsKey })
    },
  })
}

export function useMarkAllRead() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () =>
      apiFetch('/api/v1/notifications/mark_all_read', { method: 'POST' }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: notificationsKey })
    },
  })
}
