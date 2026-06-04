import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, act } from '@testing-library/react'
import { AnalysisProgress } from './AnalysisProgress'

const STEPS = ['Lendo transações', 'Identificando padrões', 'Montando sugestões']

describe('<AnalysisProgress />', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('starts on the first step', () => {
    render(<AnalysisProgress steps={STEPS} intervalMs={2000} />)
    expect(screen.getByTestId('analysis-progress-label')).toHaveTextContent('Lendo transações')
  })

  it('advances through steps over time', () => {
    render(<AnalysisProgress steps={STEPS} intervalMs={2000} />)
    act(() => { vi.advanceTimersByTime(2000) })
    expect(screen.getByTestId('analysis-progress-label')).toHaveTextContent('Identificando padrões')
    act(() => { vi.advanceTimersByTime(2000) })
    expect(screen.getByTestId('analysis-progress-label')).toHaveTextContent('Montando sugestões')
  })

  it('holds on the last step (does not overflow the list)', () => {
    render(<AnalysisProgress steps={STEPS} intervalMs={2000} />)
    act(() => { vi.advanceTimersByTime(2000 * 10) })
    expect(screen.getByTestId('analysis-progress-label')).toHaveTextContent('Montando sugestões')
  })

  it('renders a progress bar that never reaches 100% on its own', () => {
    render(<AnalysisProgress steps={STEPS} intervalMs={2000} />)
    act(() => { vi.advanceTimersByTime(2000 * 10) })
    const bar = screen.getByTestId('analysis-progress-bar')
    const width = parseFloat(bar.style.width)
    expect(width).toBeGreaterThan(0)
    expect(width).toBeLessThanOrEqual(90)
  })
})
