import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { RecorrentesPage } from './RecorrentesPage'
import type { Recurrence } from './useRecurrences'

type MockResponse = { status: number; body: unknown }

function setupFetch(
  responses: Record<string, MockResponse | ((init?: RequestInit) => MockResponse)>
) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const handler = responses[`${init?.method ?? 'GET'} ${url}`] ?? responses[url]
    if (!handler) throw new Error(`unmocked: ${init?.method ?? 'GET'} ${url}`)
    const { status, body } = typeof handler === 'function' ? handler(init) : handler
    return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { fetchMock }
}

function rec(o: Partial<Recurrence> = {}): Recurrence {
  return {
    id: 'r1',
    account_id: 'a1',
    descriptor_pattern: 'netflix',
    expected_amount_cents: 5590,
    amount_tolerance_pct: 10,
    cadence: 'monthly',
    next_expected_at: '2026-06-15',
    status: 'active',
    source: 'detected',
    ...o,
  }
}

function renderPage() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <RecorrentesPage />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<RecorrentesPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists recurrences with cadence, source badge and amount', async () => {
    setupFetch({
      '/api/v1/recurrences': { status: 200, body: { recurrences: [rec()] } },
    })
    renderPage()
    await waitFor(() => expect(screen.getByTestId('recurrence-row-r1')).toBeInTheDocument())
    expect(screen.getByText('netflix')).toBeInTheDocument()
    expect(screen.getByText('auto')).toBeInTheDocument()
    expect(screen.getByText(/Mensal/)).toBeInTheDocument()
    expect(screen.getByText(/15\/06\/2026/)).toBeInTheDocument()
    expect(screen.getByText('R$ 55,90')).toBeInTheDocument()
  })

  it('shows the empty state when there are no recurrences', async () => {
    setupFetch({ '/api/v1/recurrences': { status: 200, body: { recurrences: [] } } })
    renderPage()
    await waitFor(() => expect(screen.getByTestId('recurrences-empty')).toBeInTheDocument())
  })

  it('pauses an active recurrence from the detail sheet', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/recurrences': { status: 200, body: { recurrences: [rec()] } },
      'PATCH /api/v1/recurrences/r1': { status: 200, body: { recurrence: rec({ status: 'paused' }) } },
    })
    renderPage()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('recurrence-row-r1'))
    await user.click(await screen.findByTestId('recurrence-pause'))
    await waitFor(() => {
      const call = fetchMock.mock.calls.find(
        (c) => c[0] === '/api/v1/recurrences/r1' && c[1]?.method === 'PATCH'
      )
      expect(JSON.parse(call![1]!.body as string)).toEqual({ status: 'paused' })
    })
  })

  it('edits the tolerance from the detail sheet', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/recurrences': { status: 200, body: { recurrences: [rec()] } },
      'PATCH /api/v1/recurrences/r1': { status: 200, body: { recurrence: rec({ amount_tolerance_pct: 25 }) } },
    })
    renderPage()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('recurrence-row-r1'))
    const input = await screen.findByTestId('recurrence-tolerance')
    await user.clear(input)
    await user.type(input, '25')
    await user.click(screen.getByTestId('recurrence-save'))
    await waitFor(() => {
      const call = fetchMock.mock.calls.find(
        (c) => c[0] === '/api/v1/recurrences/r1' && c[1]?.method === 'PATCH'
      )
      expect(JSON.parse(call![1]!.body as string)).toEqual({ amount_tolerance_pct: 25 })
    })
  })

  it('cancels a recurrence from the detail sheet', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/recurrences': { status: 200, body: { recurrences: [rec()] } },
      'PATCH /api/v1/recurrences/r1': { status: 200, body: { recurrence: rec({ status: 'cancelled' }) } },
    })
    renderPage()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('recurrence-row-r1'))
    await user.click(await screen.findByTestId('recurrence-cancel'))
    await waitFor(() => {
      const call = fetchMock.mock.calls.find(
        (c) => c[0] === '/api/v1/recurrences/r1' && c[1]?.method === 'PATCH'
      )
      expect(JSON.parse(call![1]!.body as string)).toEqual({ status: 'cancelled' })
    })
  })
})
