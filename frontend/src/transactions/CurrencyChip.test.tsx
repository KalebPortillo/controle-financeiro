import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { CurrencyChip } from './CurrencyChip'

describe('CurrencyChip', () => {
  it('mostra a moeda original quando a compra foi em outra moeda', () => {
    render(<CurrencyChip currency="USD" />)
    expect(screen.getByText('USD')).toBeInTheDocument()
  })

  it('não renderiza nada quando foi na moeda da conta (null)', () => {
    const { container } = render(<CurrencyChip currency={null} />)
    expect(container).toBeEmptyDOMElement()
  })
})
