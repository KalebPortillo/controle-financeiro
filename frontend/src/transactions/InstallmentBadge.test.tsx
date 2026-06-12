import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { InstallmentBadge } from './InstallmentBadge'

describe('<InstallmentBadge />', () => {
  it('mostra "3/12"', () => {
    render(<InstallmentBadge number={3} total={12} />)
    expect(screen.getByTestId('installment-badge')).toHaveTextContent('3/12')
  })

  it('não renderiza quando não há total', () => {
    const { container } = render(<InstallmentBadge number={null} total={null} />)
    expect(container).toBeEmptyDOMElement()
  })

  it('mostra "?" quando falta o número', () => {
    render(<InstallmentBadge number={null} total={6} />)
    expect(screen.getByTestId('installment-badge')).toHaveTextContent('?/6')
  })
})
