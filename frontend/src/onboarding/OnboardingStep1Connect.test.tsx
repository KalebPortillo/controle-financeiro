import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { OnboardingStep1Connect } from './OnboardingStep1Connect'
import type { OnboardingState } from './useOnboarding'

// Mocka o ConnectBankButton — não queremos o widget Pluggy aqui. Expõe as props
// como data-attrs pra asseverar o seletor de histórico e o destaque/label do botão.
vi.mock('../bank/ConnectBankButton', () => ({
  ConnectBankButton: ({
    historySince,
    variant,
    label,
  }: {
    historySince?: string
    variant?: string
    label?: string
  }) => (
    <button
      data-testid="fake-connect-button"
      data-history-since={historySince ?? ''}
      data-variant={variant ?? 'primary'}
    >
      {label ?? 'Conectar banco'}
    </button>
  ),
}))

// Lista de conexões controlável por teste (default: nenhuma).
let mockConnections: { connections: Array<{ id: string; accounts: Array<{ institution_label?: string; name: string }> }> } = { connections: [] }
vi.mock('../bank/useBankConnections', async (orig) => {
  const actual = await orig<typeof import('../bank/useBankConnections')>()
  return { ...actual, useBankConnectionsList: () => ({ data: mockConnections }) }
})

const startAnalysisMutate = vi.fn()
// Evita a chamada de start() no mount mexer no fetch global; expõe startAnalysis.
vi.mock('./useOnboarding', async (orig) => {
  const actual = await orig<typeof import('./useOnboarding')>()
  return {
    ...actual,
    useStartOnboarding: () => ({ mutate: vi.fn(), isPending: false }),
    useStartAnalysis: () => ({ mutate: startAnalysisMutate, isPending: false }),
  }
})

const state: OnboardingState = {
  status: 'connecting',
  current_step: 1,
  started_at: '2026-06-03T00:00:00Z',
  completed_at: null,
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
    mockConnections = { connections: [] }
    startAnalysisMutate.mockClear()
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

describe('<OnboardingStep1Connect /> — continuar para análise (F2)', () => {
  beforeEach(() => {
    mockConnections = { connections: [] }
    startAnalysisMutate.mockClear()
  })

  it('disables "Continuar para análise" until a connection exists', () => {
    renderStep()
    expect(screen.getByTestId('continue-to-analysis')).toBeDisabled()
  })

  it('lists connected accounts and enables continue once connected', () => {
    mockConnections = {
      connections: [{ id: 'bc-1', accounts: [{ institution_label: 'Nubank', name: 'cc' }] }],
    }
    renderStep()
    expect(screen.getByTestId('connected-list')).toHaveTextContent('Nubank')
    expect(screen.getByTestId('continue-to-analysis')).toBeEnabled()
  })

  it('clicking continue starts the analysis (advance to analyzing)', () => {
    mockConnections = { connections: [{ id: 'bc-1', accounts: [] }] }
    renderStep()
    fireEvent.click(screen.getByTestId('continue-to-analysis'))
    expect(startAnalysisMutate).toHaveBeenCalledTimes(1)
  })

  it('connect button is primary "Conectar banco" before any connection', () => {
    mockConnections = { connections: [] }
    renderStep()
    const btn = screen.getByTestId('fake-connect-button')
    expect(btn).toHaveAttribute('data-variant', 'primary')
    expect(btn).toHaveTextContent('Conectar banco')
  })

  it('connect button becomes secondary "Conectar outro banco" once connected', () => {
    mockConnections = { connections: [{ id: 'bc-1', accounts: [] }] }
    renderStep()
    const btn = screen.getByTestId('fake-connect-button')
    expect(btn).toHaveAttribute('data-variant', 'outline')
    expect(btn).toHaveTextContent('Conectar outro banco')
  })
})
