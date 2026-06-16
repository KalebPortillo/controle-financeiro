import { describe, it, expect, beforeEach, vi } from 'vitest'
import { renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useTransactionsChannel } from './useTransactionsChannel'
import { inboxKey, type InboxPayload, type InboxTransaction } from './useInbox'

const hoisted = vi.hoisted(() => ({
  create: vi.fn(),
  unsubscribe: vi.fn(),
}))

vi.mock('../api/cable', () => ({
  getCableConsumer: () => ({ subscriptions: { create: hoisted.create } }),
}))

function tx(id: string): InboxTransaction {
  return { id, status: 'pending' } as InboxTransaction
}

function setup(workspaceId: string | null, payload?: InboxPayload) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  if (payload) qc.setQueryData<InboxPayload>(inboxKey, payload)
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
  renderHook(() => useTransactionsChannel(workspaceId), { wrapper })
  return qc
}

describe('useTransactionsChannel', () => {
  beforeEach(() => {
    hoisted.create.mockReset()
    hoisted.create.mockReturnValue({ unsubscribe: hoisted.unsubscribe })
  })

  it('assina o canal com o workspace_id', () => {
    setup('ws-1')
    expect(hoisted.create).toHaveBeenCalledWith(
      { channel: 'TransactionsChannel', workspace_id: 'ws-1' },
      expect.anything()
    )
  })

  it('não assina sem workspace', () => {
    setup(null)
    expect(hoisted.create).not.toHaveBeenCalled()
  })

  it('decisão de outro membro (status != pending) tira o item da inbox', () => {
    const qc = setup('ws-1', {
      transactions: [tx('t1'), tx('t2')],
      pending_count: 2,
    })
    const handlers = hoisted.create.mock.calls[0][1]

    handlers.received({ event: 'transaction_updated', id: 't1', status: 'consolidated' })

    const data = qc.getQueryData<InboxPayload>(inboxKey)
    expect(data?.transactions.map((t) => t.id)).toEqual(['t2'])
    expect(data?.pending_count).toBe(1)
  })

  it('status pending (sem decisão) não mexe na inbox', () => {
    const qc = setup('ws-1', { transactions: [tx('t1')], pending_count: 1 })
    const handlers = hoisted.create.mock.calls[0][1]

    handlers.received({ event: 'transaction_updated', id: 't1', status: 'pending' })

    expect(qc.getQueryData<InboxPayload>(inboxKey)?.transactions).toHaveLength(1)
  })

  it('evento desconhecido é ignorado', () => {
    const qc = setup('ws-1', { transactions: [tx('t1')], pending_count: 1 })
    const handlers = hoisted.create.mock.calls[0][1]

    handlers.received({ event: 'outro', id: 't1', status: 'consolidated' })

    expect(qc.getQueryData<InboxPayload>(inboxKey)?.transactions).toHaveLength(1)
  })
})
