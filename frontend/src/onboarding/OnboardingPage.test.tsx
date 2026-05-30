import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router'
import { OnboardingPage } from './OnboardingPage'

type MockResponse = { status: number; body: unknown }

function setupFetch(responses: Record<string, MockResponse>) {
  const calls: string[] = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    const key = `${init?.method ?? 'GET'} ${url}`
    calls.push(key)
    const handler = responses[key] ?? responses[url]
    if (!handler) throw new Error(`unmocked: ${key}`)
    return { ok: handler.status >= 200 && handler.status < 300, status: handler.status, json: async () => handler.body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { calls }
}

function renderAt(path = '/onboarding') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route path="/onboarding" element={<OnboardingPage />} />
          <Route path="/inbox" element={<p>inbox</p>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>
  )
}

const baseState = {
  status: 'not_started',
  current_step: 0,
  started_at: null,
  completed_at: null,
  suggested_tags: [],
  suggested_categories: [],
  accepted_tag_ids: [],
  accepted_category_ids: [],
}

describe('<OnboardingPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders step 1 when status is not_started', async () => {
    setupFetch({
      '/api/v1/onboarding': { status: 200, body: baseState },
      'POST /api/v1/onboarding/start': { status: 200, body: { ...baseState, status: 'connecting', current_step: 1 } },
    })
    renderAt()
    await waitFor(() => expect(screen.getByTestId('onboarding-step-1')).toBeInTheDocument())
    expect(screen.getByRole('heading', { name: /Conectar sua conta/ })).toBeInTheDocument()
  })

  it('renders waiting state when status is analyzing', async () => {
    setupFetch({
      '/api/v1/onboarding': {
        status: 200,
        body: { ...baseState, status: 'analyzing', current_step: 1, started_at: '2026-05-30T00:00:00Z' },
      },
    })
    renderAt()
    await waitFor(() => expect(screen.getByTestId('onboarding-waiting')).toBeInTheDocument())
  })

  it('shows skip-onboarding confirmation dialog', async () => {
    setupFetch({
      '/api/v1/onboarding': { status: 200, body: baseState },
      'POST /api/v1/onboarding/start': { status: 200, body: { ...baseState, status: 'connecting', current_step: 1 } },
    })
    renderAt()
    await waitFor(() => screen.getByTestId('skip-onboarding'))

    const user = userEvent.setup()
    await user.click(screen.getByTestId('skip-onboarding'))
    expect(screen.getByText(/Pular o onboarding/)).toBeInTheDocument()
  })

  it('navigates to inbox when status is completed', async () => {
    setupFetch({
      '/api/v1/onboarding': {
        status: 200,
        body: { ...baseState, status: 'completed', current_step: null, completed_at: '2026-05-30T00:00:00Z' },
      },
    })
    renderAt()
    await waitFor(() => expect(screen.getByText('inbox')).toBeInTheDocument())
  })

  it('navigates to inbox when status is skipped', async () => {
    setupFetch({
      '/api/v1/onboarding': {
        status: 200,
        body: { ...baseState, status: 'skipped' },
      },
    })
    renderAt()
    await waitFor(() => expect(screen.getByText('inbox')).toBeInTheDocument())
  })
})
