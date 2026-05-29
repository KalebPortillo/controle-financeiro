import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { GastosPage } from './GastosPage'
import type { InboxTransaction } from './useInbox'

function setupFetch(handler: (url: string) => { status: number; body: unknown }) {
  const calls: string[] = []
  const fetchMock = vi.fn().mockImplementation(async (url: string) => {
    calls.push(url)
    const { status, body } = handler(url)
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
    direction: 'debit',
    amount_cents: 31240,
    currency: 'BRL',
    occurred_at: '2026-05-19',
    original_description: 'MERCADO',
    improved_title: 'Mercado da semana',
    status: 'consolidated',
    source: 'automatic_sync',
    lock_version: 1,
    tags: [],
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
    await waitFor(() => expect(calls.some((u) => u.includes('status=consolidated'))).toBe(true))
    expect(calls.some((u) => /from=\d{4}-\d{2}-01/.test(u))).toBe(true)

    const user = userEvent.setup()
    const callsBefore = calls.length
    await user.click(screen.getByTestId('prev-month'))
    await waitFor(() => expect(calls.length).toBeGreaterThan(callsBefore))
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
