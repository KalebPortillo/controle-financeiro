import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { LoginPage } from './LoginPage'

describe('<LoginPage />', () => {
  it('renders the wallet logo, headline and Google sign-in form (POST, anti login-CSRF)', () => {
    render(<LoginPage />)
    expect(screen.getByLabelText('PortilhoWallet')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: /portilho\s*wallet/i })).toBeInTheDocument()
    const button = screen.getByTestId('google-login') as HTMLButtonElement
    expect(button).toHaveTextContent(/entrar com google/i)
    expect(button.form).toHaveAttribute('method', 'post')
    expect(button.form).toHaveAttribute('action', '/api/v1/auth/google_oauth2')
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
