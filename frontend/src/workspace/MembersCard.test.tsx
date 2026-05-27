import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MembersCard } from './MembersCard'

type MockResponse = {
  status: number
  body: unknown
}

function setupFetch(responses: Record<string, MockResponse | ((init?: RequestInit) => MockResponse)>) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const handler = responses[`${init?.method ?? 'GET'} ${url}`] ?? responses[url]
    if (!handler) throw new Error(`unmocked fetch: ${init?.method ?? 'GET'} ${url}`)
    const { status, body } = typeof handler === 'function' ? handler(init) : handler
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { fetchMock, calls }
}

function renderCard() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <QueryClientProvider client={qc}>
      <MembersCard workspaceId="w1" />
    </QueryClientProvider>
  )
}

describe('<MembersCard />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists existing members from GET /memberships', async () => {
    setupFetch({
      '/api/v1/workspaces/w1/memberships': {
        status: 200,
        body: {
          memberships: [
            {
              id: 'm1',
              role: 'editor',
              joined_at: '2026-05-27T17:00:00Z',
              user: { id: 'u1', email: 'kaleb@example.com', name: 'Kaleb Portilho', avatar_url: null },
            },
          ],
        },
      },
    })
    renderCard()
    await waitFor(() => expect(screen.getByText('Kaleb Portilho')).toBeInTheDocument())
    expect(screen.getByText('kaleb@example.com')).toBeInTheDocument()
  })

  it('posts the invite email and shows success feedback', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/workspaces/w1/memberships': {
        status: 200,
        body: { memberships: [] },
      },
      'POST /api/v1/workspaces/w1/memberships': (init) => {
        const body = JSON.parse(init!.body as string) as { email: string }
        return {
          status: 201,
          body: {
            membership: {
              id: 'm2',
              role: 'editor',
              joined_at: '2026-05-27T17:00:00Z',
              user: { id: 'u2', email: body.email, name: 'Wife', avatar_url: null },
            },
          },
        }
      },
    })
    renderCard()
    const user = userEvent.setup()
    await user.type(screen.getByTestId('invite-email'), 'wife@example.com')
    await user.click(screen.getByTestId('invite-submit'))

    await waitFor(() => expect(screen.getByTestId('invite-feedback')).toHaveTextContent(/convite adicionado/i))
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/v1/workspaces/w1/memberships',
      expect.objectContaining({ method: 'POST' })
    )
  })

  it('shows a friendly message when invite returns user_not_found', async () => {
    setupFetch({
      'GET /api/v1/workspaces/w1/memberships': { status: 200, body: { memberships: [] } },
      'POST /api/v1/workspaces/w1/memberships': {
        status: 404,
        body: { error: { code: 'user_not_found', message: 'No user.' } },
      },
    })
    renderCard()
    const user = userEvent.setup()
    await user.type(screen.getByTestId('invite-email'), 'ghost@example.com')
    await user.click(screen.getByTestId('invite-submit'))

    await waitFor(() => {
      expect(screen.getByTestId('invite-feedback')).toHaveTextContent(/ainda não tem conta/i)
    })
  })
})
