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
})
