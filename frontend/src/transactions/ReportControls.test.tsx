import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { ReportPeriodControl } from './ReportPeriodControl'
import { ReportFilters } from './ReportFilters'
import { useReportParams } from './useReportParams'

function setupFetch() {
  const responses: Record<string, unknown> = {
    'sessions/current': { user: { id: 'u1' }, workspaces: [], active_workspace_id: 'w1' },
    'workspaces/w1/memberships': { memberships: [{ id: 'm1', role: 'editor', joined_at: '', user: { id: 'u1', email: '', name: 'Ana', avatar_url: null } }] },
    'accounts': { accounts: [{ id: 'a1', name: 'Nubank', kind: 'checking', institution: 'nubank', institution_label: 'Nubank', last_digits: '1234', owner_membership_id: 'm1', currency: 'BRL' }] },
  }
  globalThis.fetch = vi.fn().mockImplementation(async (url: string) => {
    const key = Object.keys(responses).find((k) => url.includes(k))
    if (!key) throw new Error(`unmocked: ${url}`)
    return { ok: true, status: 200, json: async () => responses[key] } as Response
  }) as unknown as typeof fetch
}

function PeriodHarness() {
  const params = useReportParams()
  return (
    <div>
      <span data-testid="period-value">{params.period}</span>
      <span data-testid="mode-value">{params.mode}</span>
      <ReportPeriodControl params={params} />
    </div>
  )
}

function FiltersHarness() {
  const params = useReportParams()
  return (
    <div>
      <span data-testid="direction-value">{params.filters.direction ?? 'none'}</span>
      <span data-testid="person-value">{params.filters.membershipId ?? 'none'}</span>
      <ReportFilters params={params} />
    </div>
  )
}

function renderHarness(node: React.ReactNode, entry = '/relatorios') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[entry]}>{node}</MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('<ReportPeriodControl />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('advances and rewinds the month', async () => {
    renderHarness(<PeriodHarness />, '/relatorios?period=2026-05')
    expect(screen.getByTestId('period-value').textContent).toBe('2026-05')
    await userEvent.click(screen.getByTestId('next-month'))
    await waitFor(() => expect(screen.getByTestId('period-value').textContent).toBe('2026-06'))
    await userEvent.click(screen.getByTestId('prev-month'))
    await waitFor(() => expect(screen.getByTestId('period-value').textContent).toBe('2026-05'))
  })

  it('enters custom mode when the calendar toggle is used', async () => {
    renderHarness(<PeriodHarness />, '/relatorios?period=2026-05')
    await userEvent.click(screen.getByTestId('period-custom-open'))
    expect(screen.getByTestId('custom-from')).toBeInTheDocument()
  })
})

describe('<ReportFilters />', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
    setupFetch()
  })

  it('toggles direction to receitas and reflects it in params', async () => {
    renderHarness(<FiltersHarness />, '/relatorios?period=2026-05')
    await userEvent.click(screen.getByTestId('filters-toggle'))
    await userEvent.click(screen.getByTestId('direction-credit'))
    await waitFor(() => expect(screen.getByTestId('direction-value').textContent).toBe('credit'))
  })

  it('selects a person and shows the active filter count', async () => {
    renderHarness(<FiltersHarness />, '/relatorios?period=2026-05')
    await userEvent.click(screen.getByTestId('filters-toggle'))
    await waitFor(() => expect(screen.getByTestId('filter-person')).toBeInTheDocument())
    await userEvent.selectOptions(screen.getByTestId('filter-person'), 'm1')
    await waitFor(() => expect(screen.getByTestId('person-value').textContent).toBe('m1'))
  })

  it('toggles an account chip filter', async () => {
    renderHarness(<FiltersHarness />, '/relatorios?period=2026-05')
    await userEvent.click(screen.getByTestId('filters-toggle'))
    await waitFor(() => expect(screen.getByTestId('filter-account-a1')).toBeInTheDocument())
    await userEvent.click(screen.getByTestId('filter-account-a1'))
    await waitFor(() => expect(screen.getByTestId('filters-clear')).toBeInTheDocument())
  })
})
