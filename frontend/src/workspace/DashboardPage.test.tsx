import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { DashboardPage } from './DashboardPage'

type SessionFixture = {
  user: { id: string; email: string; name: string; avatar_url: string | null }
  workspaces: Array<{ id: string; name: string }>
  active_workspace_id: string | null
}

const buildSession = (overrides: Partial<SessionFixture> = {}): SessionFixture => ({
  user: { id: 'u1', email: 'kaleb@example.com', name: 'Kaleb Portilho', avatar_url: null },
  workspaces: [{ id: 'w1', name: "Kaleb's workspace" }],
  active_workspace_id: 'w1',
  ...overrides,
})

function setupFetch(session: SessionFixture) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (input: string, init?: RequestInit) => {
    calls.push({ url: input, init })
    if (input === '/api/v1/sessions/current' && (!init || init.method === undefined || init.method === 'GET')) {
      return {
        ok: true,
        status: 200,
        json: async () => session,
      } as Response
    }
    if (input === '/api/v1/sessions/current' && init?.method === 'DELETE') {
      return { ok: true, status: 204, json: async () => undefined } as Response
    }
    if (input === '/api/v1/sessions/current/select_workspace') {
      const body = JSON.parse(init!.body as string) as { workspace_id: string }
      return {
        ok: true,
        status: 200,
        json: async () => ({ active_workspace_id: body.workspace_id }),
      } as Response
    }
    throw new Error(`unmocked fetch: ${input}`)
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { calls, fetchMock }
}

function renderDashboard() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <DashboardPage />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<DashboardPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('greets the user and shows the active workspace', async () => {
    const session = buildSession()
    setupFetch(session)
    renderDashboard()

    await waitFor(() =>
      expect(screen.getByRole('heading', { name: /olá, kaleb/i })).toBeInTheDocument()
    )
    expect(screen.getByText("Kaleb's workspace")).toBeInTheDocument()
    expect(screen.getByText('kaleb@example.com')).toBeInTheDocument()
  })

  it('omits the workspace switcher when the user has a single workspace', async () => {
    const session = buildSession()
    setupFetch(session)
    renderDashboard()

    await waitFor(() =>
      expect(screen.getByRole('heading', { name: /olá, kaleb/i })).toBeInTheDocument()
    )
    expect(screen.queryByText('Trocar de workspace')).not.toBeInTheDocument()
  })

  it('shows the workspace switcher with >1 workspace and posts on click', async () => {
    const session = buildSession({
      workspaces: [
        { id: 'w1', name: 'Mine' },
        { id: 'w2', name: 'Casal' },
      ],
      active_workspace_id: 'w1',
    })
    const { fetchMock } = setupFetch(session)
    renderDashboard()

    await waitFor(() => expect(screen.getByText('Trocar de workspace')).toBeInTheDocument())
    const user = userEvent.setup()
    await user.click(screen.getByTestId('workspace-pick-w2'))

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/sessions/current/select_workspace',
        expect.objectContaining({ method: 'POST' })
      )
    })
  })

  it('clicking "Sair" calls DELETE /sessions/current', async () => {
    const session = buildSession()
    const { fetchMock } = setupFetch(session)
    renderDashboard()

    await waitFor(() =>
      expect(screen.getByRole('heading', { name: /olá, kaleb/i })).toBeInTheDocument()
    )

    const user = userEvent.setup()
    await user.click(screen.getByTestId('logout-button'))

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/sessions/current',
        expect.objectContaining({ method: 'DELETE' })
      )
    })
  })
})
