import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { OnboardingStep3Categories } from './OnboardingStep3Categories'
import type { OnboardingState } from './useOnboarding'

type Mock = { status: number; body: unknown }
function setupFetch(responses: Record<string, Mock>) {
  const calls: { url: string; body?: string }[] = []
  globalThis.fetch = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, body: init?.body?.toString() })
    const key = `${init?.method ?? 'GET'} ${url}`
    const handler = responses[key] ?? responses[url]
    if (!handler) {
      return { ok: true, status: 200, json: async () => ({ tags: [] }) } as Response
    }
    return { ok: handler.status >= 200 && handler.status < 300, status: handler.status, json: async () => handler.body } as Response
  }) as unknown as typeof fetch
  return calls
}

const baseState: OnboardingState = {
  status: 'categorizing',
  current_step: 3,
  started_at: '2026-05-30T00:00:00Z',
  completed_at: null,
  suggested_tags: [],
  suggested_categories: [
    { name: 'Alimentação', tag_names: [ 'Mercado', 'Padaria' ] },
    { name: 'Transporte',  tag_names: [ 'Transporte' ] },
  ],
  accepted_tag_ids: [],
  accepted_category_ids: [],
}

function renderStep(state = baseState, tags: { id: string; name: string; color: null; icon: null; usage_count: number }[] = []) {
  const qc = new QueryClient({
    defaultOptions: {
      queries: { retry: false, staleTime: Infinity },
      mutations: { retry: false },
    },
  })
  qc.setQueryData(['tags'], tags)
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <OnboardingStep3Categories state={state} />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<OnboardingStep3Categories />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders suggested categories with names', () => {
    renderStep()
    expect(screen.getByDisplayValue('Alimentação')).toBeInTheDocument()
    expect(screen.getByDisplayValue('Transporte')).toBeInTheDocument()
  })

  it('posts accepted categories with tag_ids resolved from names', async () => {
    const tags = [
      { id: 'uuid-1', name: 'Mercado', color: null, icon: null, usage_count: 0 },
      { id: 'uuid-2', name: 'Padaria', color: null, icon: null, usage_count: 0 },
    ]
    const calls = setupFetch({
      'POST /api/v1/onboarding/categories': {
        status: 200,
        body: { ...baseState, status: 'completed' },
      },
    })
    renderStep(baseState, tags)
    const user = userEvent.setup()

    await user.click(screen.getByTestId('conclude-onboarding'))
    await waitFor(() => {
      const post = calls.find((c) => c.url.includes('/onboarding/categories'))
      expect(post).toBeTruthy()
      const body = JSON.parse(post!.body!)
      const alim = body.accepted.find((c: { name: string }) => c.name === 'Alimentação')
      expect(alim).toBeTruthy()
      expect(alim.tag_ids).toContain('uuid-1')
      expect(alim.tag_ids).toContain('uuid-2')
    })
  })

  it('skip step posts with empty accepted', async () => {
    const calls = setupFetch({
      'POST /api/v1/onboarding/categories': { status: 200, body: { ...baseState, status: 'completed' } },
    })
    renderStep()
    const user = userEvent.setup()
    await user.click(screen.getByTestId('skip-categories-step'))
    await waitFor(() => {
      const post = calls.find((c) => c.url.includes('/onboarding/categories'))
      const body = JSON.parse(post!.body!)
      expect(body.accepted).toEqual([])
    })
  })

  it('adds a manual category', async () => {
    setupFetch({})
    renderStep()
    const user = userEvent.setup()
    await user.type(screen.getByTestId('manual-category-input'), 'Casa')
    await user.click(screen.getByRole('button', { name: /Adicionar/i }))
    expect(screen.getByText('Casa')).toBeInTheDocument()
  })

  it('removes a tag from a category', async () => {
    const tags = [
      { id: 'uuid-1', name: 'Mercado', color: null, icon: null, usage_count: 0 },
      { id: 'uuid-2', name: 'Padaria', color: null, icon: null, usage_count: 0 },
    ]
    setupFetch({})
    renderStep(baseState, tags)
    const user = userEvent.setup()

    const removeButtons = screen.getAllByLabelText('Remover tag')
    expect(removeButtons.length).toBeGreaterThanOrEqual(2)

    await user.click(removeButtons[0])

    const after = screen.getAllByLabelText('Remover tag')
    expect(after.length).toBe(removeButtons.length - 1)
  })
})
