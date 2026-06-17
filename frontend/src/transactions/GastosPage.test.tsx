import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { GastosPage } from './GastosPage'
import type { InboxTransaction } from './useInbox'

function setupFetch(handler: (url: string, init?: RequestInit) => { status: number; body: unknown }) {
  const calls: Array<{ url: string; method: string }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, method: init?.method ?? 'GET' })
    const { status, body } = handler(url, init)
    return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { calls }
}

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 'g1',
    account_id: 'a1',
    account_name: 'Nubank CC',
    account_kind: 'credit_card',
    institution_label: 'Nubank',
    account_institution_name: 'Nubank',
    account_brand: null,
    account_last_digits: null, card_last_digits: null,
    installment_number: null,
    installment_total: null,
    installment_group_id: null,
    purchase_date: null,
    direction: 'debit',
    amount_cents: 31240,
    currency: 'BRL',
    occurred_at: '2026-05-19',
    original_description: 'MERCADO',
    improved_title: 'Mercado da semana',
    ai_confidence: null,
    ai_suggestion: null,
    ai_status: 'analyzed',
    status: 'consolidated',
    source: 'automatic_sync',
    lock_version: 1,
    tags: [],
    effective_amount_cents: 31240,
    refund: null,
    ...o,
  }
}

function renderGastos() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <GastosPage />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<GastosPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists consolidated transactions with totals', async () => {
    setupFetch(() => ({
      status: 200,
      body: { transactions: [tx(), tx({ id: 'g2', direction: 'credit', amount_cents: 650000, improved_title: 'Salário' })], pending_count: 0 },
    }))
    renderGastos()
    await waitFor(() => expect(screen.getByText('Mercado da semana')).toBeInTheDocument())
    expect(screen.getByText('Salário')).toBeInTheDocument()
    // total de gastos (1 débito)
    expect(screen.getByText(/em 1 gastos/)).toBeInTheDocument()
  })

  it('requests consolidated for the current month and navigates months', async () => {
    const { calls } = setupFetch(() => ({ status: 200, body: { transactions: [], pending_count: 0 } }))
    renderGastos()
    await waitFor(() => expect(calls.some((c) => c.url.includes('status=consolidated'))).toBe(true))
    expect(calls.some((c) => /from=\d{4}-\d{2}-01/.test(c.url))).toBe(true)

    const user = userEvent.setup()
    const callsBefore = calls.length
    await user.click(screen.getByTestId('prev-month'))
    await waitFor(() => expect(calls.length).toBeGreaterThan(callsBefore))
  })

  it('shows the edit history when toggled in the sheet', async () => {
    setupFetch((url) => {
      if (url.includes('/api/v1/tags')) return { status: 200, body: { tags: [] } }
      if (url.includes('/edits')) {
        return {
          status: 200,
          body: {
            edits: [
              {
                id: 'e1',
                field_name: 'amount_cents',
                old_value: 1000,
                new_value: 2500,
                edited_at: '2026-05-20T10:00:00Z',
                edited_by: { id: 'm1', name: 'Kaleb' },
              },
            ],
          },
        }
      }
      return { status: 200, body: { transactions: [tx()], pending_count: 0 } }
    })
    renderGastos()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('gasto-row-g1'))
    await user.click(await screen.findByTestId('history-toggle-g1'))
    await waitFor(() => expect(screen.getByTestId('history-g1')).toBeInTheDocument())
    expect(within(screen.getByTestId('history-g1')).getByText(/Valor/)).toBeInTheDocument()
  })

  it('opens manual entry and POSTs a new transaction', async () => {
    const { calls } = setupFetch((url) => {
      if (url.includes('/api/v1/tags')) return { status: 200, body: { tags: [] } }
      if (url === '/api/v1/transactions') return { status: 201, body: { transaction: tx() } }
      return { status: 200, body: { transactions: [], pending_count: 0 } }
    })
    renderGastos()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('open-manual'))
    await user.type(screen.getByTestId('manual-amount'), '45,00')
    await user.click(screen.getByTestId('manual-submit'))

    await waitFor(() =>
      expect(calls.some((c) => c.url === '/api/v1/transactions' && c.method === 'POST')).toBe(true)
    )
  })

  it('opens the detail sheet in consolidated mode (no accept/reject)', async () => {
    setupFetch((url) => {
      if (url.includes('/api/v1/tags')) return { status: 200, body: { tags: [] } }
      return { status: 200, body: { transactions: [tx()], pending_count: 0 } }
    })
    renderGastos()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('gasto-row-g1'))
    const done = await screen.findByTestId('sheet-done-g1')
    expect(done).toBeInTheDocument()
    expect(screen.queryByTestId('sheet-accept-g1')).not.toBeInTheDocument()
    // editar/remover continuam disponíveis
    expect(within(document.body).getByTestId('sheet-remove-g1')).toBeInTheDocument()
  })
})
