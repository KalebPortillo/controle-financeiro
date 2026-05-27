import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { LoginPage } from './LoginPage'

describe('<LoginPage />', () => {
  it('renders the wallet logo, headline and Google sign-in link', () => {
    render(<LoginPage />)
    expect(screen.getByLabelText('Controle Financeiro')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: /controle financeiro/i })).toBeInTheDocument()
    const link = screen.getByTestId('google-login') as HTMLAnchorElement
    expect(link).toHaveAttribute('href', '/api/v1/auth/google_oauth2')
    expect(link).toHaveTextContent(/entrar com google/i)
  })

  it('renders an error alert when an error message is provided', () => {
    render(<LoginPage error="invalid_credentials" />)
    expect(screen.getByRole('alert')).toBeInTheDocument()
  })

  it('does not render the error alert by default', () => {
    render(<LoginPage />)
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })
})
