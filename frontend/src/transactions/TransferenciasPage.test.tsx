import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { TransferenciasPage } from './TransferenciasPage'
import type { InternalTransfer } from './useInternalTransfers'

type Handler = { status: number; body: unknown }
function setupFetch(responses: Record<string, Handler>) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const h = responses[`${init?.method ?? 'GET'} ${url}`] ?? responses[url]
    if (!h) throw new Error(`unmocked: ${init?.method ?? 'GET'} ${url}`)
    return { ok: h.status >= 200 && h.status < 300, status: h.status, json: async () => h.body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { calls }
}

function transfer(o: Partial<InternalTransfer> = {}): InternalTransfer {
  return {
    id: 'it1', manual: false, detected_at: '2026-06-04',
    debit: { id: 'd1', account_name: 'Nubank', amount_cents: 50000, occurred_at: '2026-06-04', title: 'Saída' },
    credit: { id: 'c1', account_name: 'Itaú', amount_cents: 50000, occurred_at: '2026-06-04', title: 'Entrada' },
    ...o,
  }
}

function renderPage() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <TransferenciasPage />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('<TransferenciasPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists transfers with the auto/manual badge and accounts', async () => {
    setupFetch({ '/api/v1/internal_transfers': { status: 200, body: { internal_transfers: [transfer()] } } })
    renderPage()
    const row = await screen.findByTestId('transfer-it1')
    expect(within(row).getByText('Nubank')).toBeInTheDocument()
    expect(within(row).getByText('Itaú')).toBeInTheDocument()
    expect(within(row).getByText('auto')).toBeInTheDocument()
  })

  it('shows the empty state when there are none', async () => {
    setupFetch({ '/api/v1/internal_transfers': { status: 200, body: { internal_transfers: [] } } })
    renderPage()
    await waitFor(() => expect(screen.getByTestId('transfers-empty')).toBeInTheDocument())
  })

  it('unmarks a transfer (DELETE)', async () => {
    const { calls } = setupFetch({
      '/api/v1/internal_transfers': { status: 200, body: { internal_transfers: [transfer()] } },
      'DELETE /api/v1/internal_transfers/it1': { status: 204, body: null },
    })
    renderPage()
    const row = await screen.findByTestId('transfer-it1')
    const user = userEvent.setup()
    await user.click(within(row).getByTestId('unmark-it1'))
    await waitFor(() =>
      expect(calls.find((c) => c.url === '/api/v1/internal_transfers/it1' && c.init?.method === 'DELETE')).toBeTruthy(),
    )
  })
})
