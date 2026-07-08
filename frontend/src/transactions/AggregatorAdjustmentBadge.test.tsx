import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { AggregatorAdjustmentBadge } from './AggregatorAdjustmentBadge'

describe('AggregatorAdjustmentBadge', () => {
  it('shows the label when flagged', () => {
    render(<AggregatorAdjustmentBadge show />)
    expect(screen.getByText(/ajuste de agregador/i)).toBeInTheDocument()
  })

  it('renders nothing when not flagged', () => {
    const { container } = render(<AggregatorAdjustmentBadge show={false} />)
    expect(container).toBeEmptyDOMElement()
  })

  it('renders nothing when undefined', () => {
    const { container } = render(<AggregatorAdjustmentBadge />)
    expect(container).toBeEmptyDOMElement()
  })
})
