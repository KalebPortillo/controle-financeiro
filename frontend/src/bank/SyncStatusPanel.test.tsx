import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { SyncStatusPanel } from './SyncStatusPanel'
import type { BankConnection, ConnectionStatus } from './useBankConnections'

type MockResponse = { status: number; body: unknown }

function setupFetch(
  responses: Record<string, MockResponse | ((init?: RequestInit) => MockResponse)>
) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const handler = responses[`${init?.method ?? 'GET'} ${url}`] ?? responses[url]
    if (!handler) throw new Error(`unmocked fetch: ${init?.method ?? 'GET'} ${url}`)
    const { status, body } = typeof handler === 'function' ? handler(init) : handler
    return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { fetchMock, calls }
}

function connection(overrides: Partial<BankConnection> = {}): BankConnection {
  return {
    id: 'c1',
    provider: 'pluggy',
    status: 'connected' as ConnectionStatus,
    error_message: null,
    sync_history_since: '2026-01-01',
    last_sync_at: '2026-05-28T09:00:00Z',
    next_sync_at: null,
    last_sync_created_count: 5,
    last_sync_duplicate_count: 1,
    last_sync_error_count: 0,
    last_sync_duration_seconds: 12,
    accounts: [
      {
        id: 'a1',
        name: 'Conta corrente',
        kind: 'checking',
        institution: 'nubank',
        institution_label: 'Nubank',
        currency: 'BRL',
      },
    ],
    ...overrides,
  }
}

function renderPanel() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <QueryClientProvider client={qc}>
      <SyncStatusPanel />
    </QueryClientProvider>
  )
}

describe('<SyncStatusPanel />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists connections with institution and status label', async () => {
    setupFetch({
      '/api/v1/bank_connections': {
        status: 200,
        body: { connections: [connection()], summary: { total: 1, connected: 1, syncing: 0, error: 0 } },
      },
    })
    renderPanel()
    await waitFor(() => expect(screen.getByText('Nubank')).toBeInTheDocument())
    expect(screen.getByText('Conectado')).toBeInTheDocument()
    expect(screen.getByText('Conta corrente')).toBeInTheDocument()
  })

  it('shows the error message when a connection is in error', async () => {
    setupFetch({
      '/api/v1/bank_connections': {
        status: 200,
        body: {
          connections: [connection({ status: 'error', error_message: 'Token expirado — reconecte' })],
          summary: { total: 1, connected: 0, syncing: 0, error: 1 },
        },
      },
    })
    renderPanel()
    await waitFor(() =>
      expect(screen.getByText(/token expirado/i)).toBeInTheDocument()
    )
    expect(screen.getByText('Erro')).toBeInTheDocument()
  })

  it('renders an empty state when there are no connections', async () => {
    setupFetch({
      '/api/v1/bank_connections': {
        status: 200,
        body: { connections: [], summary: { total: 0, connected: 0, syncing: 0, error: 0 } },
      },
    })
    renderPanel()
    await waitFor(() => expect(screen.getByTestId('sync-empty')).toBeInTheDocument())
  })

  it('"Sincronizar agora" posts to the per-connection sync endpoint', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/bank_connections': {
        status: 200,
        body: { connections: [connection()], summary: { total: 1, connected: 1, syncing: 0, error: 0 } },
      },
      'POST /api/v1/bank_connections/c1/sync': {
        status: 202,
        body: { bank_connection: connection({ status: 'syncing' }) },
      },
    })
    renderPanel()
    const user = userEvent.setup()
    const row = await screen.findByTestId('connection-c1')
    await user.click(within(row).getByTestId('sync-now-c1'))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/bank_connections/c1/sync',
        expect.objectContaining({ method: 'POST' })
      )
    )
  })

  it('"Sincronizar todas" posts to sync_all', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/bank_connections': {
        status: 200,
        body: { connections: [connection()], summary: { total: 1, connected: 1, syncing: 0, error: 0 } },
      },
      'POST /api/v1/bank_connections/sync_all': { status: 202, body: { enqueued: 1 } },
    })
    renderPanel()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('sync-all'))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/bank_connections/sync_all',
        expect.objectContaining({ method: 'POST' })
      )
    )
  })
})
