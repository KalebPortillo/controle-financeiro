import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { ReportsPage } from './ReportsPage'

type MockResponse = { status: number; body: unknown }

function setupFetch(responses: Record<string, MockResponse>) {
  const fetchMock = vi.fn().mockImplementation(async (url: string) => {
    const key = Object.keys(responses).find((k) => url.includes(k))
    if (!key) throw new Error(`unmocked: ${url}`)
    const { status, body } = responses[key]
    return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { fetchMock }
}

function mkOverview() {
  return {
    period: { from: '2026-05-01', to: '2026-05-31' },
    expense_cents: 350000,
    income_cents: 800000,
    balance_cents: 450000,
    top_tags: [
      { tag_id: 't1', name: 'Mercado', color: '#7C3AED', amount_cents: 120000 },
    ],
    top_categories: [
      { category_id: 'c1', name: 'Alimentação', color: '#7C3AED', amount_cents: 200000 },
    ],
    previous_period_comparison: { expense_delta_pct: -4.3, income_delta_pct: 2.1 },
  }
}

function renderReports() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <ReportsPage />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<ReportsPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders KPI cards with values from overview', async () => {
    setupFetch({
      'reports/overview': { status: 200, body: mkOverview() },
      'reports/by_tag':   { status: 200, body: { tags: [{ tag_id: 't1', name: 'Mercado', color: '#7C3AED', amount_cents: 120000, transactions_count: 3 }] } },
      'reports/by_category': { status: 200, body: { categories: [{ category_id: 'c1', name: 'Alimentação', color: null, amount_cents: 200000, transactions_count: 5, shared_with_other_categories_count: 0 }], total_distinct_transactions_amount_cents: 350000, sum_of_categories_amount_cents: 200000, overlap_present: false } },
      'reports/monthly_evolution': { status: 200, body: { months: [{ period: '2026-05', expense_cents: 350000, income_cents: 800000 }] } },
    })
    renderReports()
    await waitFor(() => expect(screen.getByText('Total gasto')).toBeInTheDocument())
    expect(screen.getByText('Total recebido')).toBeInTheDocument()
    expect(screen.getByText('Saldo do mês')).toBeInTheDocument()
  })

  it('shows delta percentage from previous period', async () => {
    setupFetch({
      'reports/overview': { status: 200, body: mkOverview() },
      'reports/by_tag':   { status: 200, body: { tags: [] } },
      'reports/by_category': { status: 200, body: { categories: [], total_distinct_transactions_amount_cents: 0, sum_of_categories_amount_cents: 0, overlap_present: false } },
      'reports/monthly_evolution': { status: 200, body: { months: [] } },
    })
    renderReports()
    await waitFor(() => expect(screen.getByText(/-4\.3% vs mês anterior/)).toBeInTheDocument())
  })

  it('shows overlap warning when overlap_present is true', async () => {
    setupFetch({
      'reports/overview': { status: 200, body: mkOverview() },
      'reports/by_tag':   { status: 200, body: { tags: [] } },
      'reports/by_category': {
        status: 200,
        body: {
          categories: [
            { category_id: 'c1', name: 'Alimentação', color: null, amount_cents: 120000, transactions_count: 2, shared_with_other_categories_count: 1 },
            { category_id: 'c2', name: 'Lazer',        color: null, amount_cents:  80000, transactions_count: 1, shared_with_other_categories_count: 1 },
          ],
          total_distinct_transactions_amount_cents: 150000,
          sum_of_categories_amount_cents: 200000,
          overlap_present: true,
        },
      },
      'reports/monthly_evolution': { status: 200, body: { months: [] } },
    })
    renderReports()
    await waitFor(() => expect(screen.getByText(/a soma pode ser maior que o total real/)).toBeInTheDocument())
  })

  it('shows empty state for tags when no data', async () => {
    setupFetch({
      'reports/overview': { status: 200, body: mkOverview() },
      'reports/by_tag':   { status: 200, body: { tags: [] } },
      'reports/by_category': { status: 200, body: { categories: [], total_distinct_transactions_amount_cents: 0, sum_of_categories_amount_cents: 0, overlap_present: false } },
      'reports/monthly_evolution': { status: 200, body: { months: [] } },
    })
    renderReports()
    await waitFor(() => expect(screen.getByText(/Nenhuma tag com gastos/)).toBeInTheDocument())
  })
})
