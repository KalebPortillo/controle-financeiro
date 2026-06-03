import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { OnboardingStep1Connect } from './OnboardingStep1Connect'
import type { OnboardingState } from './useOnboarding'

// Mocka o ConnectBankButton — não queremos o widget Pluggy aqui. Expõe a prop
// historySince como data-attr pra podermos asseverar o que o seletor calculou.
vi.mock('../bank/ConnectBankButton', () => ({
  ConnectBankButton: ({ historySince }: { historySince?: string }) => (
    <button data-testid="fake-connect-button" data-history-since={historySince ?? ''}>
      conectar
    </button>
  ),
}))

// Evita a chamada de start() no mount mexer no fetch global.
vi.mock('./useOnboarding', async (orig) => {
  const actual = await orig<typeof import('./useOnboarding')>()
  return { ...actual, useStartOnboarding: () => ({ mutate: vi.fn(), isPending: false }) }
})

const state: OnboardingState = {
  status: 'connecting',
  current_step: 1,
  started_at: '2026-06-03T00:00:00Z',
  completed_at: null,
  suggested_tags: [],
  suggested_categories: [],
  accepted_tag_ids: [],
  accepted_category_ids: [],
}

function renderStep() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <OnboardingStep1Connect state={state} />
    </QueryClientProvider>,
  )
}

function historySince(): string {
  return screen.getByTestId('fake-connect-button').getAttribute('data-history-since') ?? ''
}

describe('<OnboardingStep1Connect /> — seletor de histórico (RF1.7)', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-06-03T12:00:00'))
  })
  afterEach(() => vi.useRealTimers())

  it('defaults to last 3 months', () => {
    renderStep()
    expect(historySince()).toBe('2026-03-03')
  })

  it('updates history_since when picking "Último mês"', () => {
    renderStep()
    fireEvent.click(screen.getByRole('radio', { name: 'Último mês' }))
    expect(historySince()).toBe('2026-05-03')
  })

  it('reveals a date picker for "Personalizado" and uses its value', () => {
    renderStep()
    expect(screen.queryByTestId('custom-history-date')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('radio', { name: 'Personalizado' }))
    const picker = screen.getByTestId('custom-history-date')
    expect(picker).toBeInTheDocument()

    fireEvent.change(picker, { target: { value: '2025-11-15' } })
    expect(historySince()).toBe('2025-11-15')
  })
})
