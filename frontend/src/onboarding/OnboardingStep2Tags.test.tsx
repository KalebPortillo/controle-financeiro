import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { OnboardingStep2Tags } from './OnboardingStep2Tags'

type Handler = { status: number; body: unknown }

function setupFetch(responses: Record<string, Handler>) {
  const withDefaults: Record<string, Handler> = {
    '/api/v1/tags': { status: 200, body: { tags: [] } },
    '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [] } },
    ...responses,
  }
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const handler = withDefaults[`${init?.method ?? 'GET'} ${url}`] ?? withDefaults[url]
    if (!handler) throw new Error(`unmocked: ${init?.method ?? 'GET'} ${url}`)
    return { ok: handler.status >= 200 && handler.status < 300, status: handler.status, json: async () => handler.body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { calls, fetchMock }
}

function tag(o = {}) {
  return { id: 't1', name: 'Alimentação', color: null, icon: null, usage_count: 0, ...o }
}
function suggestion(o = {}) {
  return { id: 's1', name: 'Transporte', rationale: null, coverage: 4, source: 'detected', status: 'pending', ...o }
}

function renderStep() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <OnboardingStep2Tags />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('<OnboardingStep2Tags /> (rework: aceitas + sugeridas)', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists accepted tags and AI suggestions in separate sections', async () => {
    setupFetch({
      '/api/v1/tags': { status: 200, body: { tags: [tag()] } },
      '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [suggestion()] } },
    })
    renderStep()
    await waitFor(() => expect(screen.getByTestId('accepted-tag-t1')).toHaveTextContent('Alimentação'))
    expect(screen.getByTestId('suggested-tag-s1')).toHaveTextContent('Transporte')
  })

  it('creates a tag on the spot (it joins the accepted list)', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      'POST /api/v1/tags': { status: 201, body: { tag: tag({ name: 'Lazer' }) } },
    })
    renderStep()
    const user = userEvent.setup()
    await user.type(screen.getByTestId('new-tag-name'), 'Lazer')
    await user.click(screen.getByTestId('new-tag-submit'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith('/api/v1/tags', expect.objectContaining({ method: 'POST' })),
    )
  })

  it('accepts a suggestion via the shared list', async () => {
    const { fetchMock } = setupFetch({
      '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [suggestion()] } },
      'POST /api/v1/suggested_tags/s1/accept': { status: 200, body: { tag: tag({ name: 'Transporte' }) } },
    })
    renderStep()
    const row = await screen.findByTestId('suggested-tag-s1')
    const user = userEvent.setup()
    await user.click(within(row).getByTestId('accept-suggestion-s1'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/suggested_tags/s1/accept',
        expect.objectContaining({ method: 'POST' }),
      ),
    )
  })

  it('continue advances the onboarding (tagging→categorizing)', async () => {
    const { fetchMock } = setupFetch({
      '/api/v1/tags': { status: 200, body: { tags: [tag()] } },
      'POST /api/v1/onboarding/advance': { status: 200, body: { status: 'categorizing', current_step: 4 } },
    })
    renderStep()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('continue-tags'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/onboarding/advance',
        expect.objectContaining({ method: 'POST' }),
      ),
    )
  })
})
