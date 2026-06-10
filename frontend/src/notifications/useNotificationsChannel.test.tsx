import { describe, it, expect, beforeEach, vi } from 'vitest'
import { renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useNotificationsChannel } from './useNotificationsChannel'
import {
  notificationsKey,
  type AppNotification,
  type NotificationsPayload,
} from './useNotifications'

const hoisted = vi.hoisted(() => ({
  create: vi.fn(),
  unsubscribe: vi.fn(),
}))

vi.mock('../api/cable', () => ({
  getCableConsumer: () => ({ subscriptions: { create: hoisted.create } }),
}))

function notification(overrides: Partial<AppNotification> = {}): AppNotification {
  return {
    id: 'n1',
    kind: 'sync_failed',
    payload: { institution_label: 'Nubank' },
    read_at: null,
    created_at: '2026-06-10T12:00:00Z',
    ...overrides,
  }
}

function setup(workspaceId: string | null) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  qc.setQueryData<NotificationsPayload>(notificationsKey, {
    notifications: [],
    unread_count: 0,
  })
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
  renderHook(() => useNotificationsChannel(workspaceId), { wrapper })
  return qc
}

describe('useNotificationsChannel', () => {
  beforeEach(() => {
    hoisted.create.mockReset()
    hoisted.create.mockReturnValue({ unsubscribe: hoisted.unsubscribe })
  })

  it('assina o canal com o workspace_id', () => {
    setup('ws-1')
    expect(hoisted.create).toHaveBeenCalledWith(
      { channel: 'NotificationsChannel', workspace_id: 'ws-1' },
      expect.anything()
    )
  })

  it('não assina sem workspace', () => {
    setup(null)
    expect(hoisted.create).not.toHaveBeenCalled()
  })

  it('notification_created faz prepend e incrementa unread_count', () => {
    const qc = setup('ws-1')
    const handlers = hoisted.create.mock.calls[0][1]

    handlers.received({ event: 'notification_created', notification: notification() })

    const data = qc.getQueryData<NotificationsPayload>(notificationsKey)
    expect(data?.notifications.map((n) => n.id)).toEqual(['n1'])
    expect(data?.unread_count).toBe(1)
  })

  it('evento duplicado (mesmo id) não duplica', () => {
    const qc = setup('ws-1')
    const handlers = hoisted.create.mock.calls[0][1]

    handlers.received({ event: 'notification_created', notification: notification() })
    handlers.received({ event: 'notification_created', notification: notification() })

    const data = qc.getQueryData<NotificationsPayload>(notificationsKey)
    expect(data?.notifications).toHaveLength(1)
    expect(data?.unread_count).toBe(1)
  })

  it('inbox_new invalida a query da inbox', () => {
    const qc = setup('ws-1')
    const spy = vi.spyOn(qc, 'invalidateQueries')
    const handlers = hoisted.create.mock.calls[0][1]

    handlers.received({
      event: 'notification_created',
      notification: notification({ id: 'n2', kind: 'inbox_new', payload: { count: 3 } }),
    })

    expect(spy).toHaveBeenCalledWith({ queryKey: ['transactions', 'pending'] })
  })

  it('evento desconhecido é ignorado', () => {
    const qc = setup('ws-1')
    const handlers = hoisted.create.mock.calls[0][1]

    handlers.received({ event: 'outro', notification: notification() })

    expect(qc.getQueryData<NotificationsPayload>(notificationsKey)?.notifications).toHaveLength(0)
  })
})
