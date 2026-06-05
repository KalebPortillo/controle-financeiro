import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { Alert } from './Alert'

describe('<Alert />', () => {
  it('renders title, body and an action', () => {
    render(
      <Alert variant="warning" title="IA indisponível" action={<button>Tentar de novo</button>}>
        O limite do serviço de IA foi atingido.
      </Alert>,
    )
    expect(screen.getByRole('alert')).toBeInTheDocument()
    expect(screen.getByText('IA indisponível')).toBeInTheDocument()
    expect(screen.getByText(/limite do serviço/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Tentar de novo' })).toBeInTheDocument()
  })

  it('works without a body or action', () => {
    render(<Alert title="Erro" />)
    expect(screen.getByText('Erro')).toBeInTheDocument()
  })
})
