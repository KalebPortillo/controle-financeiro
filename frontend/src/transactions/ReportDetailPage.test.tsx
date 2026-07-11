import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router'
import { CategoryDetailPage } from './ReportDetailPage'

type MockResponse = { status: number; body: unknown }

function setupFetch(responses: Record<string, MockResponse>) {
  const base: Record<string, MockResponse> = {
    'sessions/current': { status: 200, body: { user: { id: 'u1' }, workspaces: [], active_workspace_id: 'w1' } },
    'accounts': { status: 200, body: { accounts: [] } },
    'memberships': { status: 200, body: { memberships: [] } },
  }
  const merged = { ...base, ...responses }
  const fetchMock = vi.fn().mockImplementation(async (url: string) => {
    const key = Object.keys(merged).find((k) => url.includes(k))
    if (!key) throw new Error(`unmocked: ${url}`)
    const { status, body } = merged[key]
    return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { fetchMock }
}

function mkTx(id: string, title: string, cents: number) {
  return {
    id, account_id: 'a1', account_name: 'Nubank', account_kind: 'checking',
    direction: 'debit', amount_cents: cents, currency: 'BRL', foreign_currency: null,
    occurred_at: '2026-05-10', original_description: title, improved_title: title,
    status: 'consolidated', source: 'automatic_sync', tags: [],
    effective_amount_cents: cents, refund: null, related: null, recurrence: null,
    installment_number: null, installment_total: null, installment_group_id: null,
    purchase_date: null, lock_version: 0, ai_status: 'analyzed', ai_confidence: null, ai_suggestion: null,
  }
}

function mkDetail() {
  return {
    id: 'c1', name: 'Alimentação', color: '#7C3AED',
    period: { from: '2026-05-01', to: '2026-05-31' },
    summary: { amount_cents: 145000, transactions_count: 2, share_pct: 23.7, previous_amount_cents: 132000, delta_pct: 9.8 },
    breakdown: [{ id: 't1', name: 'Mercado', color: null, amount_cents: 82000, transactions_count: 1 }],
    transactions: [mkTx('tx1', 'Pão de Açúcar', 82000), mkTx('tx2', 'Zaffari', 63000)],
  }
}

function renderDetail() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/relatorios/categoria/c1?period=2026-05']}>
        <Routes>
          <Route path="/relatorios/categoria/:id" element={<CategoryDetailPage />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('<ReportDetailPage /> (category)', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders summary, breakdown and transactions', async () => {
    setupFetch({ 'reports/category/c1': { status: 200, body: mkDetail() } })
    renderDetail()
    await waitFor(() => expect(screen.getByText('Alimentação')).toBeInTheDocument())
    // summary
    expect(screen.getByText('Participação')).toBeInTheDocument()
    expect(screen.getByText('23,7%')).toBeInTheDocument()
    expect(screen.getByText('+9.8%')).toBeInTheDocument()
    // breakdown (tag-membro)
    expect(screen.getByText('Mercado')).toBeInTheDocument()
    // transactions
    expect(screen.getByTestId('gasto-row-tx1')).toBeInTheDocument()
    expect(screen.getByTestId('gasto-row-tx2')).toBeInTheDocument()
  })

  it('opens the transaction detail sheet when a row is clicked', async () => {
    setupFetch({ 'reports/category/c1': { status: 200, body: mkDetail() } })
    renderDetail()
    await waitFor(() => expect(screen.getByTestId('gasto-row-tx1')).toBeInTheDocument())
    await userEvent.click(screen.getByTestId('gasto-row-tx1'))
    // o sheet do detalhe mostra o título da transação
    await waitFor(() => expect(screen.getAllByText('Pão de Açúcar').length).toBeGreaterThan(1))
  })

  it('shows error state on 404', async () => {
    setupFetch({ 'reports/category/c1': { status: 404, body: { error: {} } } })
    renderDetail()
    await waitFor(() => expect(screen.getByTestId('detail-error')).toBeInTheDocument())
  })
})
