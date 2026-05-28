import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { InboxPage } from './InboxPage'
import type { InboxTransaction } from './useInbox'

type MockResponse = { status: number; body: unknown }

function setupFetch(
  responses: Record<string, MockResponse | ((init?: RequestInit) => MockResponse)>
) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const handler = responses[`${init?.method ?? 'GET'} ${url}`] ?? responses[url]
    if (!handler) throw new Error(`unmocked: ${init?.method ?? 'GET'} ${url}`)
    const { status, body } = typeof handler === 'function' ? handler(init) : handler
    return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { fetchMock, calls }
}

function tx(overrides: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 't1',
    account_id: 'a1',
    account_name: 'Nubank CC',
    direction: 'debit',
    amount_cents: 2500,
    currency: 'BRL',
    occurred_at: '2026-05-20',
    original_description: 'PADARIA CENTRAL',
    improved_title: null,
    status: 'pending',
    source: 'automatic_sync',
    lock_version: 0,
    tags: [],
    ...overrides,
  }
}

function renderInbox() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <InboxPage />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<InboxPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists pending transactions in the table', async () => {
    setupFetch({
      '/api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx()], pending_count: 1 },
      },
    })
    renderInbox()
    await waitFor(() => expect(screen.getByText('PADARIA CENTRAL')).toBeInTheDocument())
    expect(screen.getByTestId('inbox-row-t1')).toBeInTheDocument()
  })

  it('shows an empty state when nothing is pending', async () => {
    setupFetch({
      '/api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [], pending_count: 0 },
      },
    })
    renderInbox()
    await waitFor(() => expect(screen.getByTestId('inbox-empty')).toBeInTheDocument())
  })

  it('opens the detail sheet on row click and accepts via consolidate', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx()], pending_count: 1 },
      },
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      'POST /api/v1/transactions/t1/consolidate': { status: 200, body: { transaction: tx({ status: 'consolidated' }) } },
    })
    renderInbox()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('inbox-row-t1'))
    await user.click(await screen.findByTestId('sheet-accept-t1'))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/transactions/t1/consolidate',
        expect.objectContaining({ method: 'POST' })
      )
    )
  })

  it('edits the title in the sheet and PATCHes with lock_version on blur', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx({ lock_version: 4 })], pending_count: 1 },
      },
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      'PATCH /api/v1/transactions/t1': { status: 200, body: { transaction: tx() } },
    })
    renderInbox()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('inbox-row-t1'))
    const title = await screen.findByTestId('sheet-title-t1')
    await user.clear(title)
    await user.type(title, 'Almoço')
    await user.tab() // blur

    await waitFor(() => {
      const call = fetchMock.mock.calls.find(
        (c) => c[0] === '/api/v1/transactions/t1' && c[1]?.method === 'PATCH'
      )
      expect(call).toBeTruthy()
      const body = JSON.parse(call![1]!.body as string)
      expect(body.lock_version).toBe(4)
      expect(body.improved_title).toBe('Almoço')
    })
  })

  it('swiping a row left accepts it (consolidate), without opening the sheet', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx()], pending_count: 1 },
      },
      'POST /api/v1/transactions/t1/consolidate': { status: 200, body: { transaction: tx() } },
    })
    renderInbox()
    const row = await screen.findByTestId('inbox-row-t1')
    // arrasta pra esquerda além do limiar e solta
    fireEvent.pointerDown(row, { clientX: 240, pointerId: 1 })
    fireEvent.pointerMove(row, { clientX: 100, pointerId: 1 })
    fireEvent.pointerUp(row, { clientX: 100, pointerId: 1 })

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/transactions/t1/consolidate',
        expect.objectContaining({ method: 'POST' })
      )
    )
    expect(screen.queryByTestId('sheet-accept-t1')).not.toBeInTheDocument()
  })

  it('swiping a row right rejects it', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx()], pending_count: 1 },
      },
      'POST /api/v1/transactions/t1/reject': { status: 200, body: { transaction: tx() } },
    })
    renderInbox()
    const row = await screen.findByTestId('inbox-row-t1')
    fireEvent.pointerDown(row, { clientX: 100, pointerId: 1 })
    fireEvent.pointerMove(row, { clientX: 240, pointerId: 1 })
    fireEvent.pointerUp(row, { clientX: 240, pointerId: 1 })

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/transactions/t1/reject',
        expect.objectContaining({ method: 'POST' })
      )
    )
  })

  it('bulk-accepts selected rows', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx({ id: 't1' }), tx({ id: 't2' })], pending_count: 2 },
      },
      'POST /api/v1/transactions/t1/consolidate': { status: 200, body: { transaction: tx() } },
      'POST /api/v1/transactions/t2/consolidate': { status: 200, body: { transaction: tx({ id: 't2' }) } },
    })
    renderInbox()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('select-t1'))
    await user.click(await screen.findByTestId('select-t2'))
    await user.click(await screen.findByTestId('bulk-accept'))

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/transactions/t1/consolidate',
        expect.objectContaining({ method: 'POST' })
      )
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/transactions/t2/consolidate',
        expect.objectContaining({ method: 'POST' })
      )
    })
  })
})
