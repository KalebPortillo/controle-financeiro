import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { GlobalSyncIndicator } from './GlobalSyncIndicator'
import type { ConnectionsSummary } from './useBankConnections'

function setupFetch(summary: ConnectionsSummary) {
  globalThis.fetch = vi.fn().mockImplementation(async (url: string) => {
    if (url === '/api/v1/bank_connections') {
      return { ok: true, status: 200, json: async () => ({ connections: [], summary }) } as Response
    }
    throw new Error(`unmocked: ${url}`)
  }) as unknown as typeof fetch
}

function renderIndicator() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <GlobalSyncIndicator />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<GlobalSyncIndicator />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders nothing when there are no connections', async () => {
    setupFetch({ total: 0, connected: 0, syncing: 0, error: 0 })
    const { container } = renderIndicator()
    // dá tempo do query resolver e confirma que segue vazio
    await waitFor(() => expect(container.querySelector('[data-testid="global-sync-indicator"]')).toBeNull())
  })

  it('prioritizes error over syncing/connected and links to /contas', async () => {
    setupFetch({ total: 3, connected: 1, syncing: 1, error: 1 })
    renderIndicator()
    const el = await screen.findByTestId('global-sync-indicator')
    expect(el).toHaveTextContent('1 com erro')
    expect(el).toHaveAttribute('href', '/contas')
  })

  it('shows connected count when all healthy', async () => {
    setupFetch({ total: 2, connected: 2, syncing: 0, error: 0 })
    renderIndicator()
    const el = await screen.findByTestId('global-sync-indicator')
    expect(el).toHaveTextContent('2 conectadas')
  })
})
