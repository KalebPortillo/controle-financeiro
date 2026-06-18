import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route, useSearchParams } from 'react-router'
import { AppLayout } from './AppLayout'

type Summary = { total: number; connected: number; syncing: number; error: number }
const NO_CONNECTIONS: Summary = { total: 0, connected: 0, syncing: 0, error: 0 }

function setupFetch(summary: Summary = NO_CONNECTIONS) {
  const calls: Array<{ url: string; method: string }> = []
  globalThis.fetch = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, method: init?.method ?? 'GET' })
    if (url === '/api/v1/sessions/current') {
      return {
        ok: true,
        status: 200,
        json: async () => ({
          user: { id: 'u1', email: 'kaleb@example.com', name: 'Kaleb Portilho', avatar_url: null },
          workspaces: [{ id: 'w1', name: "Casa do Kaleb" }],
          active_workspace_id: 'w1',
        }),
      } as Response
    }
    if (url === '/api/v1/bank_connections/sync_all') {
      return { ok: true, status: 202, json: async () => ({ enqueued: summary.total }) } as Response
    }
    if (url.startsWith('/api/v1/transactions')) {
      return { ok: true, status: 200, json: async () => ({ transactions: [], pending_count: 0 }) } as Response
    }
    // GlobalSyncIndicator/SyncAllButton no topbar buscam isso; total 0 → não renderizam.
    if (url === '/api/v1/bank_connections') {
      return { ok: true, status: 200, json: async () => ({ connections: [], summary }) } as Response
    }
    throw new Error(`unmocked: ${url}`)
  }) as unknown as typeof fetch
  return { calls }
}

function renderShell() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/']}>
        <Routes>
          <Route element={<AppLayout />}>
            <Route path="/" element={<div>conteúdo</div>} />
            <Route
              path="/gastos"
              element={<GastosRouteProbe />}
            />
          </Route>
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>
  )
}

// Sonda: mostra o ?q da URL pra assertar a navegação da busca da TopBar.
function GastosRouteProbe() {
  const [params] = useSearchParams()
  return <div>gastos q={params.get('q')}</div>
}

describe('<AppLayout />', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
    localStorage.clear()
    document.documentElement.removeAttribute('data-theme')
  })

  it('renders nav, workspace footer and the routed content', async () => {
    setupFetch()
    renderShell()
    expect(screen.getByTestId('nav-inbox')).toBeInTheDocument()
    expect(screen.getByText('conteúdo')).toBeInTheDocument()
    await waitFor(() => expect(screen.getByText('Casa do Kaleb')).toBeInTheDocument())
  })

  it('marks not-yet-built screens as "em breve"', async () => {
    setupFetch()
    renderShell()
    const orcamentos = screen.getByTestId('nav-orcamentos')
    expect(orcamentos).toHaveTextContent('em breve')
    expect(orcamentos.tagName).not.toBe('A') // não navegável
  })

  it('topbar search navigates to /gastos with the typed query', async () => {
    setupFetch()
    renderShell()
    const user = userEvent.setup()
    await user.type(screen.getByTestId('topbar-search'), 'amazon{Enter}')
    await waitFor(() => expect(screen.getByText('gastos q=amazon')).toBeInTheDocument())
  })

  it('does not render the theme toggle in the top bar (moved to "Mais")', async () => {
    setupFetch()
    renderShell()
    await waitFor(() => expect(screen.getByText('Casa do Kaleb')).toBeInTheDocument())
    expect(screen.queryByTestId('theme-toggle')).not.toBeInTheDocument()
  })

  it('top bar sync button forces a sync of all connections', async () => {
    const { calls } = setupFetch({ total: 1, connected: 1, syncing: 0, error: 0 })
    renderShell()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('sync-all-button'))
    await waitFor(() =>
      expect(
        calls.some((c) => c.url === '/api/v1/bank_connections/sync_all' && c.method === 'POST')
      ).toBe(true)
    )
  })

  it('hides the sync button when there are no connections', async () => {
    setupFetch()
    renderShell()
    await waitFor(() => expect(screen.getByText('Casa do Kaleb')).toBeInTheDocument())
    expect(screen.queryByTestId('sync-all-button')).not.toBeInTheDocument()
  })
})
