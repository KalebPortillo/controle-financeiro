import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { OnboardingStep2Tags } from './OnboardingStep2Tags'
import type { OnboardingState } from './useOnboarding'

type Mock = { status: number; body: unknown }
function setupFetch(responses: Record<string, Mock>) {
  const calls: { url: string; body?: string }[] = []
  globalThis.fetch = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, body: init?.body?.toString() })
    const key = `${init?.method ?? 'GET'} ${url}`
    const handler = responses[key] ?? responses[url]
    if (!handler) throw new Error(`unmocked: ${key}`)
    return { ok: handler.status >= 200 && handler.status < 300, status: handler.status, json: async () => handler.body } as Response
  }) as unknown as typeof fetch
  return calls
}

const baseState: OnboardingState = {
  status: 'tagging',
  current_step: 2,
  started_at: '2026-05-30T00:00:00Z',
  completed_at: null,
  suggested_tags: [
    { name: 'Mercado', rationale: '8 transações em mercados', coverage: 8 },
    { name: 'Comida fora', rationale: '5 restaurantes', coverage: 5 },
    { name: 'Transporte', rationale: '3 Uber', coverage: 3 },
  ],
  suggested_categories: [],
  accepted_tag_ids: [],
  accepted_category_ids: [],
}

function renderStep(state = baseState) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <OnboardingStep2Tags state={state} />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<OnboardingStep2Tags />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders suggested tags with rationale', () => {
    renderStep()
    expect(screen.getByDisplayValue('Mercado')).toBeInTheDocument()
    expect(screen.getByText(/8 transações em mercados/)).toBeInTheDocument()
  })

  it('selects first 5 by default', () => {
    renderStep()
    const checkbox = screen.getByTestId('tag-checkbox-Mercado') as HTMLInputElement
    expect(checkbox.checked).toBe(true)
  })

  it('submits accepted tags on Continue', async () => {
    const calls = setupFetch({
      'POST /api/v1/onboarding/tags': { status: 200, body: { ...baseState, status: 'categorizing' } },
    })
    renderStep()
    const user = userEvent.setup()
    await user.click(screen.getByTestId('continue-tags'))

    await waitFor(() => {
      const post = calls.find((c) => c.url.includes('/onboarding/tags'))
      expect(post).toBeTruthy()
      const body = JSON.parse(post!.body!)
      expect(body.accepted.length).toBe(3)
      expect(body.accepted.map((t: { name: string }) => t.name)).toContain('Mercado')
    })
  })

  it('allows editing tag name before accepting', async () => {
    const calls = setupFetch({
      'POST /api/v1/onboarding/tags': { status: 200, body: { ...baseState, status: 'categorizing' } },
    })
    renderStep()
    const user = userEvent.setup()
    const input = screen.getByTestId('tag-name-Mercado') as HTMLInputElement
    await user.clear(input)
    await user.type(input, 'Supermercado')

    await user.click(screen.getByTestId('continue-tags'))
    await waitFor(() => {
      const post = calls.find((c) => c.url.includes('/onboarding/tags'))
      const body = JSON.parse(post!.body!)
      expect(body.accepted.find((t: { name: string }) => t.name === 'Supermercado')).toBeTruthy()
    })
  })

  it('dismisses a suggestion', async () => {
    renderStep()
    const user = userEvent.setup()
    expect(screen.queryByDisplayValue('Mercado')).toBeInTheDocument()
    await user.click(screen.getByTestId('tag-dismiss-Mercado'))
    expect(screen.queryByDisplayValue('Mercado')).not.toBeInTheDocument()
  })

  it('adds a manual tag', async () => {
    setupFetch({})
    renderStep()
    const user = userEvent.setup()
    await user.type(screen.getByTestId('manual-tag-input'), 'Casa')
    await user.click(screen.getByRole('button', { name: /Adicionar/i }))
    expect(screen.getByTestId('manual-tag-list')).toHaveTextContent('Casa')
  })

  it('skip step still posts with empty accepted', async () => {
    const calls = setupFetch({
      'POST /api/v1/onboarding/tags': { status: 200, body: { ...baseState, status: 'categorizing' } },
    })
    renderStep()
    const user = userEvent.setup()
    await user.click(screen.getByTestId('skip-tags-step'))
    await waitFor(() => {
      const post = calls.find((c) => c.url.includes('/onboarding/tags'))
      const body = JSON.parse(post!.body!)
      expect(body.accepted).toEqual([])
    })
  })

  it('shows "Mostrar mais" when there are more than 10 suggestions', () => {
    const many = {
      ...baseState,
      suggested_tags: Array.from({ length: 15 }, (_, i) => ({ name: `Tag ${i}`, coverage: 1 })),
    }
    renderStep(many)
    expect(screen.getByTestId('show-more-tags')).toBeInTheDocument()
  })
})
