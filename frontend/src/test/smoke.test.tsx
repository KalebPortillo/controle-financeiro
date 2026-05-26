import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'

describe('test stack smoke', () => {
  it('Vitest runs synchronous assertions', () => {
    expect(1 + 1).toBe(2)
  })

  it('renders a React element via Testing Library + jsdom', () => {
    render(<h1>controle financeiro</h1>)
    expect(screen.getByRole('heading')).toHaveTextContent('controle financeiro')
  })
})
