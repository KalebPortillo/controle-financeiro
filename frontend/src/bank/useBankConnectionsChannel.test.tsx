import { describe, it, expect, beforeEach, vi } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useBankConnectionsChannel } from './useBankConnectionsChannel'
import { bankConnectionsKey, type BankConnection, type BankConnectionsList } from './useBankConnections'

// Captura os args do subscriptions.create pra disparar `received` manualmente.
const hoisted = vi.hoisted(() => ({
  create: vi.fn(),
  unsubscribe: vi.fn(),
}))

vi.mock('../api/cable', () => ({
  getCableConsumer: () => ({ subscriptions: { create: hoisted.create } }),
}))

function conn(overrides: Partial<BankConnection> = {}): BankConnection {
  return {
    id: 'c1',
    provider: 'pluggy',
    status: 'syncing',
    error_message: null,
    sync_history_since: '2026-01-01',
    last_sync_at: null,
    next_sync_at: null,
    last_sync_created_count: 0,
    last_sync_duplicate_count: 0,
    last_sync_error_count: 0,
    last_sync_duration_seconds: null,
    accounts: [],
    ...overrides,
  }
}

function setup(workspaceId: string | null) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  qc.setQueryData<BankConnectionsList>(bankConnectionsKey, {
    connections: [conn({ status: 'syncing' })],
    summary: { total: 1, connected: 0, syncing: 1, error: 0 },
  })
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
  renderHook(() => useBankConnectionsChannel(workspaceId), { wrapper })
  return qc
}

describe('useBankConnectionsChannel', () => {
  beforeEach(() => {
    hoisted.create.mockReset().mockReturnValue({ unsubscribe: hoisted.unsubscribe })
    hoisted.unsubscribe.mockReset()
  })

  it('subscribes to BankConnectionsChannel scoped by workspace', () => {
    setup('w1')
    expect(hoisted.create).toHaveBeenCalledWith(
      { channel: 'BankConnectionsChannel', workspace_id: 'w1' },
      expect.objectContaining({ received: expect.any(Function) })
    )
  })

  it('does not subscribe without a workspace id', () => {
    setup(null)
    expect(hoisted.create).not.toHaveBeenCalled()
  })

  it('merges a connection_updated event into the query cache', async () => {
    const qc = setup('w1')
    const [, handlers] = hoisted.create.mock.calls[0] as [
      unknown,
      { received: (data: unknown) => void },
    ]

    handlers.received({
      event: 'connection_updated',
      bank_connection: conn({ status: 'connected', last_sync_at: '2026-05-28T10:00:00Z' }),
    })

    await waitFor(() => {
      const data = qc.getQueryData<BankConnectionsList>(bankConnectionsKey)
      expect(data?.connections[0].status).toBe('connected')
      expect(data?.summary).toEqual({ total: 1, connected: 1, syncing: 0, error: 0 })
    })
  })

  it('invalidates the sync_history query for the updated connection', () => {
    const qc = setup('w1')
    const spy = vi.spyOn(qc, 'invalidateQueries')
    const [, handlers] = hoisted.create.mock.calls[0] as [
      unknown,
      { received: (data: unknown) => void },
    ]

    handlers.received({
      event: 'connection_updated',
      bank_connection: conn({ id: 'c1', status: 'connected' }),
    })

    expect(spy).toHaveBeenCalledWith({ queryKey: ['sync_history', 'c1'] })
  })

  it('ignores events that are not connection_updated', () => {
    const qc = setup('w1')
    const [, handlers] = hoisted.create.mock.calls[0] as [
      unknown,
      { received: (data: unknown) => void },
    ]

    handlers.received({ event: 'something_else', bank_connection: conn({ status: 'connected' }) })

    expect(qc.getQueryData<BankConnectionsList>(bankConnectionsKey)?.connections[0].status).toBe(
      'syncing'
    )
  })
})
