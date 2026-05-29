import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router'
import { AppLayout } from './AppLayout'

function setupFetch() {
  globalThis.fetch = vi.fn().mockImplementation(async (url: string) => {
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
    if (url.startsWith('/api/v1/transactions')) {
      return { ok: true, status: 200, json: async () => ({ transactions: [], pending_count: 0 }) } as Response
    }
    // GlobalSyncIndicator no topbar busca isso; sem conexões → não renderiza nada.
    if (url === '/api/v1/bank_connections') {
      return { ok: true, status: 200, json: async () => ({ connections: [], summary: { total: 0, connected: 0, syncing: 0, error: 0 } }) } as Response
    }
    throw new Error(`unmocked: ${url}`)
  }) as unknown as typeof fetch
}

function renderShell() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/']}>
        <Routes>
          <Route element={<AppLayout />}>
            <Route path="/" element={<div>conteúdo</div>} />
          </Route>
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>
  )
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

  it('theme toggle flips data-theme on <html>', async () => {
    setupFetch()
    renderShell()
    const user = userEvent.setup()
    const before = document.documentElement.getAttribute('data-theme')
    await user.click(screen.getByTestId('theme-toggle'))
    await waitFor(() =>
      expect(document.documentElement.getAttribute('data-theme')).not.toBe(before)
    )
  })
})
