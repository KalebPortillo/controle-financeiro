import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { RelatedSection } from './RelatedSection'
import type { InboxTransaction, RelatedItem } from './useInbox'

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 'buy1', account_id: 'a1', account_name: 'Nubank', direction: 'debit',
    account_kind: 'credit_card', institution_label: 'Nubank', account_institution_name: 'Nubank',
    account_brand: null, account_last_digits: null, card_last_digits: null,
    installment_number: null, installment_total: null, installment_group_id: null,
    purchase_date: null, foreign_currency: 'USD',
    amount_cents: 6527, currency: 'BRL', occurred_at: '2026-06-20',
    original_description: 'STORE US', improved_title: 'Compra US', ai_confidence: null,
    ai_suggestion: null, ai_status: 'analyzed', status: 'consolidated', source: 'automatic_sync',
    lock_version: 0, tags: [], effective_amount_cents: 6527, refund: null, related: null, ...o,
  }
}

const iofItem: RelatedItem = {
  link_id: 'l1', relation_type: 'iof', role: 'satellite', transaction_id: 'iof1',
  title: 'IOF de compra internacional', direction: 'debit', amount_cents: 228,
  occurred_at: '2026-06-22', status: 'consolidated',
}

function setupFetch() {
  const calls: Array<{ url: string; method: string }> = []
  globalThis.fetch = vi.fn(async (url: string, init?: RequestInit) => {
    calls.push({ url, method: init?.method ?? 'GET' })
    return { ok: true, status: 204, json: async () => ({}) } as Response
  }) as unknown as typeof fetch
  return { calls }
}

function renderSection(transaction: InboxTransaction) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <RelatedSection transaction={transaction} />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('<RelatedSection />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders nothing when there are no related links', () => {
    renderSection(tx({ related: null }))
    expect(screen.queryByTestId('related-section')).not.toBeInTheDocument()
  })

  it('lists an IOF satellite of the purchase', () => {
    setupFetch()
    renderSection(tx({ related: [iofItem] }))
    expect(screen.getByTestId('related-section')).toBeInTheDocument()
    expect(screen.getByTestId('related-iof1')).toHaveTextContent('IOF')
  })

  it('shows the origin purchase when this is the IOF (role origin)', () => {
    setupFetch()
    renderSection(tx({ related: [{ ...iofItem, role: 'origin', transaction_id: 'buy9', title: 'Compra US' }] }))
    expect(screen.getByTestId('related-buy9')).toHaveTextContent('Origem · Compra US')
  })

  it('unlinks via DELETE /transaction_links/:id', async () => {
    const { calls } = setupFetch()
    renderSection(tx({ related: [iofItem] }))
    const user = userEvent.setup()
    await user.click(screen.getByTestId('related-unlink-l1'))
    await waitFor(() =>
      expect(calls.some((c) => c.url === '/api/v1/transaction_links/l1' && c.method === 'DELETE')).toBe(true)
    )
  })
})
