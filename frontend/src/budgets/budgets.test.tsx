import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { BudgetsPage } from './BudgetsPage'
import type { Budget } from './useBudgets'

function budget(o: Partial<Budget> = {}): Budget {
  return {
    id: 'b1', name: 'Mercado', kind: 'tag', monthly_limit_cents: 80_000, alert_threshold_pct: 80,
    enabled: true, starts_on: null, ends_on: null,
    target_tag: { id: 't1', name: 'Mercado', color: null }, target_category: null, composite_tags: [],
    overlap: false,
    progress: { spent_cents: 42_300, limit_cents: 80_000, pct: 53, status: 'ok', projection_cents: 75_000, remaining_cents: 37_700 },
    ...o,
  }
}

let budgetsData: Budget[]
let posted: unknown
beforeEach(() => {
  budgetsData = [budget()]
  posted = null
  globalThis.fetch = vi.fn((url: string, opts?: RequestInit) => {
    const u = String(url)
    if (u.includes('/api/v1/budgets') && opts?.method === 'POST') {
      posted = JSON.parse(opts.body as string)
      return Promise.resolve({ ok: true, status: 201, json: async () => ({ budget: budget() }) } as Response)
    }
    if (u.includes('/api/v1/budgets')) return Promise.resolve({ ok: true, status: 200, json: async () => ({ period: { from: '2026-06-01', to: '2026-06-30' }, budgets: budgetsData }) } as Response)
    if (u.includes('/api/v1/tags')) return Promise.resolve({ ok: true, status: 200, json: async () => ({ tags: [{ id: 't1', name: 'Mercado', color: null, icon: null, usage_count: 3 }] }) } as Response)
    if (u.includes('/api/v1/categories')) return Promise.resolve({ ok: true, status: 200, json: async () => ({ categories: [], ai_error: null }) } as Response)
    return Promise.resolve({ ok: true, status: 200, json: async () => ({}) } as Response)
  }) as unknown as typeof fetch
})

function renderPage() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <BudgetsPage />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('BudgetsPage', () => {
  it('renders a budget card with spent, limit and pct', async () => {
    renderPage()
    expect(await screen.findByTestId('budget-card-b1')).toBeInTheDocument()
    expect(screen.getByTestId('budget-pct-b1')).toHaveTextContent('53%')
    const card = screen.getByTestId('budget-card-b1')
    expect(card).toHaveTextContent('Mercado')
  })

  it('marks the progress bar with the status', async () => {
    budgetsData = [budget({ progress: { spent_cents: 90_000, limit_cents: 80_000, pct: 113, status: 'exceeded', projection_cents: 90_000, remaining_cents: -10_000 } })]
    renderPage()
    await screen.findByTestId('budget-card-b1')
    expect(screen.getByRole('progressbar')).toHaveAttribute('data-status', 'exceeded')
  })

  it('empty state shows a CTA when there are no budgets', async () => {
    budgetsData = []
    renderPage()
    expect(await screen.findByTestId('budgets-empty')).toBeInTheDocument()
  })

  it('wizard: pick a tag, set limit, save → POSTs the right body', async () => {
    budgetsData = []
    renderPage()
    await screen.findByTestId('budgets-empty')

    await userEvent.click(screen.getByTestId('budget-new'))
    // step 1: kind tag is default; pick the tag
    await userEvent.click(await screen.findByTestId('budget-tag-list-t1'))
    await userEvent.click(screen.getByTestId('budget-next'))
    // step 2
    await userEvent.type(screen.getByTestId('budget-name'), 'Mercado')
    await userEvent.type(screen.getByTestId('budget-limit'), '800,00')
    await userEvent.click(screen.getByTestId('budget-save'))

    await waitFor(() => {
      expect(posted).toMatchObject({
        name: 'Mercado', kind: 'tag', target_tag_id: 't1', monthly_limit_cents: 80_000,
      })
    })
  })
})
