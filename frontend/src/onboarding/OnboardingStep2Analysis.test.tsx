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
  analysis_error: null,
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

  it('shows a friendly error card (not a spinner) when analysis failed', async () => {
    setupFetch({
      'GET /api/v1/onboarding': {
        status: 200,
        body: {
          status: 'analyzing', current_step: 2, started_at: null, completed_at: null,
          analysis_error: { reason: 'quota', message: 'O limite do serviço de IA foi atingido.', at: '2026-06-05T00:00:00Z' },
        },
      },
    })
    renderStep()

    await waitFor(() => expect(screen.getByTestId('analysis-error')).toBeInTheDocument())
    expect(screen.getByText(/limite do serviço de IA/i)).toBeInTheDocument()
    expect(screen.queryByTestId('analysis-progress-bar')).not.toBeInTheDocument()
    expect(screen.getByTestId('continue-manually')).toBeInTheDocument()
  })

  it('continue-manually advances to tagging', async () => {
    const { calls } = setupFetch({
      'GET /api/v1/onboarding': {
        status: 200,
        body: {
          status: 'analyzing', current_step: 2, started_at: null, completed_at: null,
          analysis_error: { reason: 'quota', message: 'Limite atingido.', at: '2026-06-05T00:00:00Z' },
        },
      },
      'POST /api/v1/onboarding/advance': { status: 200, body: taggingState },
      'GET /api/v1/session': { status: 200, body: {} },
    })
    renderStep()

    const user = userEvent.setup()
    await user.click(await screen.findByTestId('continue-manually'))
    await waitFor(() =>
      expect(calls.find((c) => c.url === '/api/v1/onboarding/advance')).toBeTruthy()
    )
    const advanceCall = calls.find((c) => c.url === '/api/v1/onboarding/advance')
    expect(JSON.parse(advanceCall!.body!)).toEqual({ to: 'tagging' })
  })
})
