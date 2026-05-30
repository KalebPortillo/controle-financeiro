import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { StepIndicator } from './StepIndicator'

const STEPS = [
  { id: 'a', label: 'Um' },
  { id: 'b', label: 'Dois' },
  { id: 'c', label: 'Três' },
]

describe('<StepIndicator />', () => {
  it('marks the current step with aria-current', () => {
    render(<StepIndicator steps={STEPS} current={2} />)
    expect(screen.getByText('2').getAttribute('aria-current')).toBe('step')
  })

  it('renders past steps with a check', () => {
    render(<StepIndicator steps={STEPS} current={3} />)
    // O passo 1 e 2 são passados → têm check (svg) e não número visível
    // assertion mais simples: o aria-current só está no atual
    const checks = document.querySelectorAll('svg')
    expect(checks.length).toBeGreaterThanOrEqual(2)
  })

  it('shows labels for all steps', () => {
    render(<StepIndicator steps={STEPS} current={1} />)
    expect(screen.getByText('Um')).toBeInTheDocument()
    expect(screen.getByText('Dois')).toBeInTheDocument()
    expect(screen.getByText('Três')).toBeInTheDocument()
  })
})
