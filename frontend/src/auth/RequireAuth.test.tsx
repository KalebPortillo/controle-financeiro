import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router'
import { RequireAuth } from './RequireAuth'

function renderWith(initial: string, fetchImpl: typeof fetch) {
  globalThis.fetch = fetchImpl
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[initial]}>
        <Routes>
          <Route path="/" element={<RequireAuth><div>protected</div></RequireAuth>} />
          <Route path="/login" element={<div>login screen</div>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>
  )
}

// Sessão com um dado status de onboarding — pra exercitar o gate do RequireAuth.
function sessionWithOnboarding(status: string | null) {
  return vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => ({
      user: { id: 'u1', email: 'k@x.com', name: 'K', avatar_url: null },
      workspaces: [{ id: 'w1', name: 'Mine' }],
      active_workspace_id: 'w1',
      onboarding: status ? { status, current_step: null } : null,
    }),
  } as Response) as unknown as typeof fetch
}

// Monta as rotas /onboarding e /inbox, ambas guardadas, pra observar o redirect.
function renderGate(initial: string, status: string | null) {
  globalThis.fetch = sessionWithOnboarding(status)
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[initial]}>
        <Routes>
          <Route path="/onboarding" element={<RequireAuth><div>onboarding flow</div></RequireAuth>} />
          <Route path="/inbox" element={<RequireAuth><div>inbox app</div></RequireAuth>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<RequireAuth />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders children when /sessions/current returns a session', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        user: { id: 'u1', email: 'k@x.com', name: 'K', avatar_url: null },
        workspaces: [{ id: 'w1', name: 'Mine' }],
        active_workspace_id: 'w1',
      }),
    } as Response) as unknown as typeof fetch
    renderWith('/', fetchImpl)
    await waitFor(() => expect(screen.getByText('protected')).toBeInTheDocument())
  })

  it('redirects to /login when /sessions/current returns 401', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: false,
      status: 401,
      json: async () => ({ error: { code: 'unauthenticated', message: 'no' } }),
    } as Response) as unknown as typeof fetch
    renderWith('/', fetchImpl)
    await waitFor(() => expect(screen.getByText('login screen')).toBeInTheDocument())
  })

  // Gate de onboarding (RF22) — a origem do loop pós-"Concluir": o guard decide
  // pelo status de onboarding da SESSÃO. Status terminal precisa liberar o app.
  it.each(['not_started', 'connecting', 'analyzing', 'tagging', 'categorizing'])(
    'redirects an active onboarding (%s) from the app to /onboarding',
    async (status) => {
      renderGate('/inbox', status)
      await waitFor(() => expect(screen.getByText('onboarding flow')).toBeInTheDocument())
      expect(screen.queryByText('inbox app')).not.toBeInTheDocument()
    },
  )

  it.each(['completed', 'skipped'])(
    'renders the app when onboarding is terminal (%s) — no bounce to /onboarding',
    async (status) => {
      renderGate('/inbox', status)
      await waitFor(() => expect(screen.getByText('inbox app')).toBeInTheDocument())
      expect(screen.queryByText('onboarding flow')).not.toBeInTheDocument()
    },
  )

  it('does not redirect when already in the onboarding flow (avoids loop)', async () => {
    renderGate('/onboarding', 'tagging')
    await waitFor(() => expect(screen.getByText('onboarding flow')).toBeInTheDocument())
  })
})
