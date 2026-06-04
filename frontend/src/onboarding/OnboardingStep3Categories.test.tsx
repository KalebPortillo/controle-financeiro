import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { OnboardingStep3Categories } from './OnboardingStep3Categories'
import type { OnboardingState } from './useOnboarding'

type Handler = { status: number; body: unknown }

function setupFetch(responses: Record<string, Handler>) {
  const withDefaults: Record<string, Handler> = {
    '/api/v1/categories': { status: 200, body: { categories: [] } },
    '/api/v1/suggested_categories': { status: 200, body: { suggested_categories: [] } },
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

const state: OnboardingState = {
  status: 'categorizing',
  current_step: 4,
  started_at: '2026-06-04T00:00:00Z',
  completed_at: null,
}

function category(o = {}) {
  return { id: 'c1', name: 'Essenciais', color: null, icon: null, tags: [{ id: 't1', name: 'Alimentação', color: null, icon: null }], ...o }
}
function suggestion(o = {}) {
  return { id: 'sc1', name: 'Moradia', tag_names: ['Contas da casa'], status: 'pending', ...o }
}

function renderStep() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <OnboardingStep3Categories state={state} />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('<OnboardingStep3Categories /> (rework: aceitas + sugeridas)', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists accepted categories and AI suggestions in separate sections', async () => {
    setupFetch({
      '/api/v1/categories': { status: 200, body: { categories: [category()] } },
      '/api/v1/suggested_categories': { status: 200, body: { suggested_categories: [suggestion()] } },
    })
    renderStep()
    await waitFor(() => expect(screen.getByTestId('accepted-category-c1')).toHaveTextContent('Essenciais'))
    expect(screen.getByTestId('suggested-category-sc1')).toHaveTextContent('Moradia')
  })

  it('accepts a suggested category (POST accept)', async () => {
    const { fetchMock } = setupFetch({
      '/api/v1/categories': { status: 200, body: { categories: [category()] } },
      '/api/v1/suggested_categories': { status: 200, body: { suggested_categories: [suggestion()] } },
      'POST /api/v1/suggested_categories/sc1/accept': { status: 200, body: { category: category({ id: 'c2', name: 'Moradia' }) } },
    })
    renderStep()
    const row = await screen.findByTestId('suggested-category-sc1')
    const user = userEvent.setup()
    await user.click(within(row).getByTestId('accept-suggested-category-sc1'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/suggested_categories/sc1/accept',
        expect.objectContaining({ method: 'POST' }),
      ),
    )
  })

  it('creates a category on the spot', async () => {
    const { fetchMock } = setupFetch({
      '/api/v1/categories': { status: 200, body: { categories: [category()] } },
      'POST /api/v1/categories': { status: 201, body: { category: category({ id: 'c3', name: 'Lazer' }) } },
    })
    renderStep()
    await screen.findByTestId('accepted-category-c1')
    const user = userEvent.setup()
    await user.type(screen.getByTestId('new-category-name'), 'Lazer')
    await user.click(screen.getByTestId('new-category-submit'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith('/api/v1/categories', expect.objectContaining({ method: 'POST' })),
    )
  })

  it('shows the analysis progress while the 2nd analysis has no suggestions yet', async () => {
    // categorizing, nada aceito e nada sugerido ainda → barra de progresso,
    // não uma lista vazia silenciosa (regressão do reload manual).
    setupFetch({
      '/api/v1/categories': { status: 200, body: { categories: [] } },
      '/api/v1/suggested_categories': { status: 200, body: { suggested_categories: [] } },
    })
    renderStep()
    await waitFor(() =>
      expect(screen.getByTestId('categories-analysis-progress')).toBeInTheDocument(),
    )
    expect(screen.queryByTestId('categories-empty')).not.toBeInTheDocument()
  })

  it('conclude advances the onboarding (categorizing→completed)', async () => {
    const { fetchMock } = setupFetch({
      '/api/v1/categories': { status: 200, body: { categories: [category()] } },
      'POST /api/v1/onboarding/advance': { status: 200, body: { status: 'completed', current_step: null } },
    })
    renderStep()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('conclude-onboarding'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/onboarding/advance',
        expect.objectContaining({ method: 'POST' }),
      ),
    )
  })
})
