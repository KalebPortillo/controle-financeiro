import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { useAiSuggestionRun, type AiSuggestionMessages } from './useAiSuggestionRun'

const toast = {
  loading: vi.fn<(...a: unknown[]) => string>(() => 'toast-1'),
  success: vi.fn(),
  message: vi.fn(),
  dismiss: vi.fn(),
}
vi.mock('sonner', () => ({
  toast: {
    loading: (...a: unknown[]) => toast.loading(...a),
    success: (...a: unknown[]) => toast.success(...a),
    message: (...a: unknown[]) => toast.message(...a),
    dismiss: (...a: unknown[]) => toast.dismiss(...a),
  },
}))

const messages: AiSuggestionMessages = {
  loading: 'Analisando…',
  ready: (n) => `${n} prontas`,
  empty: 'Nada novo',
}

// Helper: renderHook com props controláveis (count/hasError/active mutáveis).
function setup(initial: { active: boolean; count: number; hasError: boolean }) {
  const onFinish = vi.fn()
  let props = { ...initial }
  const view = renderHook(
    (p: typeof initial) =>
      useAiSuggestionRun({ ...p, onFinish, messages, deadlineMs: 1000 }),
    { initialProps: props }
  )
  const set = (next: Partial<typeof initial>) => {
    props = { ...props, ...next }
    act(() => view.rerender(props))
  }
  return { view, set, onFinish }
}

describe('useAiSuggestionRun', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.useFakeTimers()
  })
  afterEach(() => vi.useRealTimers())

  it('start dispara o toast de loading', () => {
    const { view } = setup({ active: false, count: 0, hasError: false })
    act(() => view.result.current.start(0))
    expect(toast.loading).toHaveBeenCalledWith('Analisando…')
  })

  it('sucesso quando a contagem aumenta: success toast + onFinish', () => {
    const { view, set, onFinish } = setup({ active: false, count: 2, hasError: false })
    act(() => view.result.current.start(2)) // baseline = 2
    set({ active: true })
    set({ count: 5 })
    expect(toast.success).toHaveBeenCalledWith('3 prontas', expect.objectContaining({ id: 'toast-1' }))
    expect(onFinish).toHaveBeenCalled()
  })

  it('prazo estourado sem novidades: message toast + onFinish', () => {
    const { view, set, onFinish } = setup({ active: false, count: 0, hasError: false })
    act(() => view.result.current.start(0))
    set({ active: true })
    act(() => vi.advanceTimersByTime(1000))
    expect(toast.message).toHaveBeenCalledWith('Nada novo', expect.objectContaining({ id: 'toast-1', duration: expect.any(Number) }))
    expect(onFinish).toHaveBeenCalled()
  })

  it('erro descarta o loading e chama onFinish (sem success)', () => {
    const { view, set, onFinish } = setup({ active: false, count: 0, hasError: false })
    act(() => view.result.current.start(0))
    set({ active: true })
    set({ hasError: true })
    expect(toast.dismiss).toHaveBeenCalledWith('toast-1')
    expect(onFinish).toHaveBeenCalled()
    expect(toast.success).not.toHaveBeenCalled()
  })

  it('não dispara o aviso de prazo depois de encerrar por sucesso', () => {
    const { view, set } = setup({ active: false, count: 0, hasError: false })
    act(() => view.result.current.start(0))
    set({ active: true })
    set({ count: 1 })
    expect(toast.success).toHaveBeenCalled()
    set({ active: false }) // onFinish encerraria via componente
    act(() => vi.advanceTimersByTime(2000))
    expect(toast.message).not.toHaveBeenCalled()
  })
})
