import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import {
  useConsolidate,
  useBulkConsolidate,
  useUpdateTransaction,
  inboxKey,
  consolidatedKey,
  searchKey,
  type InboxPayload,
  type InboxTransaction,
} from './useInbox'

// Os helpers de cache só tocam id / installment_group_id / tags, então um
// objeto mínimo (cast) basta pra exercitar a lógica sem montar tudo.
const t = (id: string, extra: Partial<InboxTransaction> = {}) =>
  ({ id, installment_group_id: null, tags: [], ...extra }) as InboxTransaction

function mockFetch(reply: () => { status: number; body: unknown }) {
  const fn = vi.fn(async () => {
    const { status, body } = reply()
    return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
  })
  globalThis.fetch = fn as unknown as typeof fetch
  return fn
}

function setup(seed: InboxPayload) {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  qc.setQueryData<InboxPayload>(inboxKey, seed)
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
  return { qc, wrapper }
}

const inbox = (qc: QueryClient) => qc.getQueryData<InboxPayload>(inboxKey)!

describe('useInbox — cache cirúrgico (sem refetch da lista)', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('useConsolidate remove o item do cache na hora, sem refazer a lista', async () => {
    const fetchMock = mockFetch(() => ({ status: 200, body: { transaction: t('a') } }))
    const { qc, wrapper } = setup({ transactions: [t('a'), t('b')], pending_count: 2 })

    const { result } = renderHook(() => useConsolidate(), { wrapper })
    await act(async () => { await result.current.mutateAsync('a') })

    expect(inbox(qc).transactions.map((x) => x.id)).toEqual(['b'])
    expect(inbox(qc).pending_count).toBe(1)
    // exatamente 1 request (o POST consolidate) — não recarregou a lista
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('faz rollback do cache quando a request falha', async () => {
    mockFetch(() => ({ status: 500, body: { error: { message: 'x' } } }))
    const { qc, wrapper } = setup({ transactions: [t('a'), t('b')], pending_count: 2 })

    const { result } = renderHook(() => useConsolidate(), { wrapper })
    await act(async () => { await result.current.mutateAsync('a').catch(() => {}) })

    expect(inbox(qc).transactions.map((x) => x.id).sort()).toEqual(['a', 'b'])
    expect(inbox(qc).pending_count).toBe(2)
  })

  it('useBulkConsolidate remove todos os ids de uma vez', async () => {
    mockFetch(() => ({ status: 200, body: { count: 2 } }))
    const { qc, wrapper } = setup({ transactions: [t('a'), t('b'), t('c')], pending_count: 3 })

    const { result } = renderHook(() => useBulkConsolidate(), { wrapper })
    await act(async () => { await result.current.mutateAsync(['a', 'c']) })

    expect(inbox(qc).transactions.map((x) => x.id)).toEqual(['b'])
    expect(inbox(qc).pending_count).toBe(1)
  })

  it('useUpdateTransaction substitui o item pelo retorno da API (ex.: nova tag)', async () => {
    const updated = t('a', { tags: [{ id: 'tg1', name: 'Mercado', color: null, icon: null }] })
    mockFetch(() => ({ status: 200, body: { transaction: updated } }))
    const { qc, wrapper } = setup({ transactions: [t('a'), t('b')], pending_count: 2 })

    const { result } = renderHook(() => useUpdateTransaction(), { wrapper })
    await act(async () => {
      await result.current.mutateAsync({ id: 'a', lock_version: 0, tag_ids: ['tg1'] })
    })

    expect(inbox(qc).transactions).toHaveLength(2) // substituiu, não removeu
    expect(inbox(qc).transactions.find((x) => x.id === 'a')!.tags).toHaveLength(1)
  })

  it('useUpdateTransaction também atualiza a tag no cache de CONSOLIDADOS e de BUSCA', async () => {
    const updated = t('a', { tags: [{ id: 'tg1', name: 'Mercado', color: null, icon: null }] })
    mockFetch(() => ({ status: 200, body: { transaction: updated } }))
    const period = '2026-07'
    const query = 'padaria'
    const { qc, wrapper } = setup({ transactions: [], pending_count: 0 })
    // a transação vive nas listas de consolidados e de busca, não na inbox
    qc.setQueryData<InboxPayload>(consolidatedKey(period), { transactions: [t('a'), t('b')], pending_count: 0 })
    qc.setQueryData<InboxPayload>(searchKey(query), { transactions: [t('a')], pending_count: 0 })
    // cache de shape diferente sob a mesma raiz ['transactions'] — não pode quebrar
    qc.setQueryData(['transactions', 'analysis_progress'], { total: 0, done: true })

    const { result } = renderHook(() => useUpdateTransaction(), { wrapper })
    await act(async () => {
      await result.current.mutateAsync({ id: 'a', lock_version: 0, tag_ids: ['tg1'] })
    })

    const cons = qc.getQueryData<InboxPayload>(consolidatedKey(period))!
    expect(cons.transactions.find((x) => x.id === 'a')!.tags).toHaveLength(1)
    const srch = qc.getQueryData<InboxPayload>(searchKey(query))!
    expect(srch.transactions.find((x) => x.id === 'a')!.tags).toHaveLength(1)
  })
})
