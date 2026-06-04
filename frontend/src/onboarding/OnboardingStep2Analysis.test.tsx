import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { OnboardingStep2Analysis } from './OnboardingStep2Analysis'

type MockResponse = { status: number; body: unknown }

function setupFetch(responses: Record<string, MockResponse>) {
  const calls: Array<{ url: string; body?: string }> = []
  const mock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, body: init?.body?.toString() })
    const key = `${init?.method ?? 'GET'} ${url}`
    const handler = responses[key] ?? responses[url]
    if (!handler) throw new Error(`unmocked: ${key}`)
    return { ok: handler.status >= 200, status: handler.status, json: async () => handler.body } as Response
  })
  globalThis.fetch = mock as unknown as typeof fetch
  return { calls }
}

const taggingState = {
  status: 'tagging' as const,
  current_step: 3,
  started_at: '2026-05-31T00:00:00Z',
  completed_at: null,
}

function renderStep() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <OnboardingStep2Analysis />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<OnboardingStep2Analysis />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders the analysis waiting screen', () => {
    setupFetch({})
    renderStep()
    expect(screen.getByTestId('onboarding-step-2')).toBeInTheDocument()
    expect(screen.getByText(/Analisando seus gastos/)).toBeInTheDocument()
    expect(screen.getByTestId('skip-analysis')).toBeInTheDocument()
  })

  it('skip analysis calls advance with to=tagging', async () => {
    const { calls } = setupFetch({
      'POST /api/v1/onboarding/advance': { status: 200, body: taggingState },
      'GET /api/v1/session': { status: 200, body: {} },
    })
    renderStep()
    const user = userEvent.setup()
    await user.click(screen.getByTestId('skip-analysis'))
    await waitFor(() =>
      expect(calls.find((c) => c.url === '/api/v1/onboarding/advance')).toBeTruthy()
    )
    const advanceCall = calls.find((c) => c.url === '/api/v1/onboarding/advance')
    expect(JSON.parse(advanceCall!.body!)).toEqual({ to: 'tagging' })
  })
})
