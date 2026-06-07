import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RefundSection } from './RefundSection'
import type { InboxTransaction } from './useInbox'

type Handler = { status: number; body: unknown }
function setupFetch(responses: Record<string, Handler>) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const h = responses[`${init?.method ?? 'GET'} ${url}`] ?? responses[url]
    if (!h) throw new Error(`unmocked: ${init?.method ?? 'GET'} ${url}`)
    return { ok: h.status >= 200 && h.status < 300, status: h.status, json: async () => h.body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { calls }
}

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 'c1', account_id: 'a1', account_name: 'Nubank', direction: 'credit',
    amount_cents: 5000, currency: 'BRL', occurred_at: '2026-06-04',
    original_description: 'ESTORNO LOJA', improved_title: null, ai_confidence: null,
    ai_suggestion: null, ai_status: 'analyzed', status: 'pending', source: 'automatic_sync', lock_version: 0,
    tags: [], effective_amount_cents: 5000, refund: null, ...o,
  }
}

function renderSection(transaction: InboxTransaction) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <RefundSection transaction={transaction} />
    </QueryClientProvider>,
  )
}

describe('<RefundSection />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders nothing for a debit with no refund', () => {
    setupFetch({})
    const { container } = renderSection(tx({ direction: 'debit', refund: null }))
    expect(container).toBeEmptyDOMElement()
  })

  it('lets a credit be linked to a candidate debit', async () => {
    const { calls } = setupFetch({
      '/api/v1/transactions/c1/refund_candidates': {
        status: 200,
        body: { refund_candidates: [tx({ id: 'd1', direction: 'debit', original_description: 'COMPRA LOJA', amount_cents: 5000 })] },
      },
      'POST /api/v1/transactions/c1/link_refund': { status: 201, body: { transaction: tx() } },
    })
    renderSection(tx())
    const user = userEvent.setup()
    await user.click(screen.getByTestId('refund-open'))
    const candidate = await screen.findByTestId('refund-candidate-d1')
    await user.click(within(candidate).getByText('COMPRA LOJA'))
    await waitFor(() => {
      const post = calls.find((c) => c.url === '/api/v1/transactions/c1/link_refund' && c.init?.method === 'POST')
      expect(post).toBeTruthy()
      expect(JSON.parse(post!.init!.body as string)).toEqual({ refunded_transaction_id: 'd1' })
    })
  })

  it('shows the effective amount and unlink for a refunded debit', async () => {
    const { calls } = setupFetch({
      'DELETE /api/v1/transaction_refunds/r1': { status: 204, body: null },
    })
    const debit = tx({
      id: 'd1', direction: 'debit', amount_cents: 10_000, effective_amount_cents: 6_000,
      refund: { refunded_amount_cents: 4_000, refunds: [{ id: 'r1', refund_transaction_id: 'c1', amount_cents: 4_000, confirmed_at: '2026-06-04' }] },
    })
    renderSection(debit)
    expect(screen.getByTestId('refund-summary')).toBeInTheDocument()
    const user = userEvent.setup()
    await user.click(screen.getByTestId('refund-unlink'))
    await waitFor(() =>
      expect(calls.find((c) => c.url === '/api/v1/transaction_refunds/r1' && c.init?.method === 'DELETE')).toBeTruthy(),
    )
  })
})
