import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { RecurringSection } from './RecurringSection'
import type { InboxTransaction } from './useInbox'

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 'g1', account_id: 'a1', account_name: 'Nubank', direction: 'debit',
    account_kind: 'credit_card', institution_label: 'Nubank', account_institution_name: 'Nubank',
    account_brand: null, account_last_digits: null, card_last_digits: null,
    installment_number: null, installment_total: null, installment_group_id: null,
    purchase_date: null, foreign_currency: null,
    amount_cents: 5590, currency: 'BRL', occurred_at: '2026-06-20',
    original_description: 'NETFLIX.COM', improved_title: 'Netflix', ai_confidence: null,
    ai_suggestion: null, ai_status: 'analyzed', status: 'consolidated', source: 'automatic_sync',
    lock_version: 0, tags: [], effective_amount_cents: 5590, refund: null, related: null, ...o,
  }
}

function setupFetch() {
  const calls: Array<{ url: string; method: string; body?: string }> = []
  globalThis.fetch = vi.fn(async (url: string, init?: RequestInit) => {
    calls.push({ url, method: init?.method ?? 'GET', body: init?.body as string })
    return { ok: true, status: 201, json: async () => ({ recurrence: { id: 'r1' } }) } as Response
  }) as unknown as typeof fetch
  return { calls }
}

function renderSection(transaction: InboxTransaction) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <RecurringSection transaction={transaction} />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('<RecurringSection />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders nothing for credits (only expenses become recurring)', () => {
    renderSection(tx({ direction: 'credit' }))
    expect(screen.queryByTestId('mark-recurring-g1')).not.toBeInTheDocument()
  })

  it('marks the expense as recurring via POST /recurrences', async () => {
    const { calls } = setupFetch()
    renderSection(tx())
    const user = userEvent.setup()
    await user.click(screen.getByTestId('mark-recurring-g1'))
    await waitFor(() => {
      const call = calls.find((c) => c.url === '/api/v1/recurrences' && c.method === 'POST')
      expect(call).toBeTruthy()
      expect(JSON.parse(call!.body!)).toEqual({ transaction_id: 'g1' })
    })
  })

  it('shows the recurrence membership state instead of the mark button', () => {
    renderSection(tx({ recurrence: { id: 'r1', descriptor_pattern: 'NETFLIX COM' } }))
    expect(screen.getByText('Está em Recorrentes')).toBeInTheDocument()
    expect(screen.queryByTestId('mark-recurring-g1')).not.toBeInTheDocument()
  })

  it('removes the expense from the recurrence via POST exclusions', async () => {
    const { calls } = setupFetch()
    renderSection(tx({ recurrence: { id: 'r1', descriptor_pattern: 'NETFLIX COM' } }))
    const user = userEvent.setup()
    await user.click(screen.getByTestId('remove-recurring-g1'))
    await waitFor(() => {
      const call = calls.find(
        (c) => c.url === '/api/v1/recurrences/r1/exclusions' && c.method === 'POST',
      )
      expect(call).toBeTruthy()
      expect(JSON.parse(call!.body!)).toEqual({ transaction_id: 'g1' })
    })
  })
})
