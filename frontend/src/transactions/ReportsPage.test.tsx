import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router'
import { ReportsPage } from './ReportsPage'

type MockResponse = { status: number; body: unknown }

// Respostas base compartilhadas (session/accounts/memberships pros filtros).
function baseResponses(): Record<string, MockResponse> {
  return {
    'sessions/current': { status: 200, body: { user: { id: 'u1' }, workspaces: [], active_workspace_id: 'w1' } },
    'accounts': { status: 200, body: { accounts: [] } },
    'memberships': { status: 200, body: { memberships: [] } },
  }
}

function setupFetch(responses: Record<string, MockResponse>) {
  const merged = { ...baseResponses(), ...responses }
  const fetchMock = vi.fn().mockImplementation(async (url: string) => {
    const key = Object.keys(merged).find((k) => url.includes(k))
    if (!key) throw new Error(`unmocked: ${url}`)
    const { status, body } = merged[key]
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
    top_tags: [{ tag_id: 't1', name: 'Mercado', color: '#7C3AED', amount_cents: 120000 }],
    top_categories: [{ category_id: 'c1', name: 'Alimentação', color: '#7C3AED', amount_cents: 200000 }],
    previous_period_comparison: { expense_delta_pct: -4.3, income_delta_pct: 2.1 },
  }
}

function fullReports(extra: Record<string, MockResponse> = {}) {
  return {
    'reports/overview': { status: 200, body: mkOverview() },
    'reports/by_tag': { status: 200, body: { tags: [{ tag_id: 't1', name: 'Mercado', color: '#7C3AED', amount_cents: 120000, transactions_count: 3 }] } },
    'reports/by_category': { status: 200, body: { categories: [{ category_id: 'c1', name: 'Alimentação', color: null, amount_cents: 200000, transactions_count: 5, shared_with_other_categories_count: 0 }], total_distinct_transactions_amount_cents: 350000, sum_of_categories_amount_cents: 200000, overlap_present: false } },
    'reports/monthly_evolution': { status: 200, body: { months: [{ period: '2026-05', expense_cents: 350000, income_cents: 800000 }] } },
    ...extra,
  }
}

function renderReports(initialEntries = ['/relatorios']) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  const seen: string[] = []
  function LocationSpy() {
    return null
  }
  const result = render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={initialEntries}>
        <Routes>
          <Route path="/relatorios" element={<ReportsPage />} />
          <Route path="/relatorios/categoria/:id" element={<CapturePath cb={(p) => seen.push(p)} label="cat" />} />
          <Route path="/relatorios/tag/:id" element={<CapturePath cb={(p) => seen.push(p)} label="tag" />} />
        </Routes>
        <LocationSpy />
      </MemoryRouter>
    </QueryClientProvider>,
  )
  return { ...result, seen }
}

function CapturePath({ cb, label }: { cb: (p: string) => void; label: string }) {
  // Registra a rota alcançada pra assertion de navegação.
  cb(label)
  return <div data-testid={`detail-${label}`}>detalhe {label}</div>
}

describe('<ReportsPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders KPI cards with values from overview', async () => {
    setupFetch(fullReports())
    renderReports()
    await waitFor(() => expect(screen.getByText('Total gasto')).toBeInTheDocument())
    expect(screen.getByText('Total recebido')).toBeInTheDocument()
    expect(screen.getByText('Saldo do período')).toBeInTheDocument()
  })

  it('shows delta percentage from previous period', async () => {
    setupFetch(fullReports())
    renderReports()
    await waitFor(() => expect(screen.getByText(/-4\.3% vs período anterior/)).toBeInTheDocument())
  })

  it('shows overlap warning when overlap_present is true', async () => {
    setupFetch(
      fullReports({
        'reports/by_category': {
          status: 200,
          body: {
            categories: [
              { category_id: 'c1', name: 'Alimentação', color: null, amount_cents: 120000, transactions_count: 2, shared_with_other_categories_count: 1 },
              { category_id: 'c2', name: 'Lazer', color: null, amount_cents: 80000, transactions_count: 1, shared_with_other_categories_count: 1 },
            ],
            total_distinct_transactions_amount_cents: 150000,
            sum_of_categories_amount_cents: 200000,
            overlap_present: true,
          },
        },
      }),
    )
    renderReports()
    await waitFor(() => expect(screen.getByText(/a soma pode ser maior que o total real/)).toBeInTheDocument())
  })

  it('navigates to category detail when a donut legend row is clicked', async () => {
    setupFetch(fullReports())
    const { seen } = renderReports()
    await waitFor(() => expect(screen.getByTestId('donut-cat-c1')).toBeInTheDocument())
    await userEvent.click(screen.getByTestId('donut-cat-c1'))
    await waitFor(() => expect(seen).toContain('cat'))
  })

  it('navigates to tag detail when a top-tag bar is clicked', async () => {
    setupFetch(fullReports())
    const { seen } = renderReports()
    await waitFor(() => expect(screen.getByTestId('hbar-tag-t1')).toBeInTheDocument())
    await userEvent.click(screen.getByTestId('hbar-tag-t1'))
    await waitFor(() => expect(seen).toContain('tag'))
  })

  it('switches to custom period inputs and requests a range', async () => {
    const { fetchMock } = setupFetch(fullReports())
    renderReports()
    await waitFor(() => expect(screen.getByTestId('period-custom-open')).toBeInTheDocument())
    await userEvent.click(screen.getByTestId('period-custom-open'))
    expect(screen.getByTestId('custom-from')).toBeInTheDocument()
    fireEvent.change(screen.getByTestId('custom-from'), { target: { value: '2026-03-01' } })
    fireEvent.change(screen.getByTestId('custom-to'), { target: { value: '2026-03-15' } })
    await waitFor(() => {
      const called = fetchMock.mock.calls.some((call) => String(call[0]).includes('from=2026-03-01') && String(call[0]).includes('to=2026-03-15'))
      expect(called).toBe(true)
    })
  })
})
