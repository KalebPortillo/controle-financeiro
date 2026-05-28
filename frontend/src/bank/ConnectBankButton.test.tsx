import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ConnectBankButton } from './ConnectBankButton'

// Mock do widget Pluggy — não queremos carregar o iframe externo no teste.
// Renderizamos um botão "fake" que dispara onSuccess com um item fixo.
vi.mock('react-pluggy-connect', () => ({
  PluggyConnect: ({ onSuccess }: { onSuccess: (d: { item: { id: string } }) => void }) => (
    <button data-testid="fake-pluggy-widget" onClick={() => onSuccess({ item: { id: 'item-xyz' } })}>
      fake widget
    </button>
  ),
}))

function setupFetch() {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    if (url === '/api/v1/bank_connections/connect_token') {
      return { ok: true, status: 200, json: async () => ({ connect_token: 'tok-1' }) } as Response
    }
    if (url === '/api/v1/bank_connections') {
      return {
        ok: true,
        status: 201,
        json: async () => ({
          bank_connection: { id: 'bc-1', provider: 'pluggy', status: 'connected', accounts: [] },
        }),
      } as Response
    }
    throw new Error(`unmocked: ${url}`)
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { calls, fetchMock }
}

function renderButton(onConnected = vi.fn()) {
  const qc = new QueryClient({ defaultOptions: { mutations: { retry: false }, queries: { retry: false } } })
  render(
    <QueryClientProvider client={qc}>
      <ConnectBankButton onConnected={onConnected} />
    </QueryClientProvider>,
  )
  return onConnected
}

describe('<ConnectBankButton />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('fetches connect token then renders the widget', async () => {
    setupFetch()
    renderButton()
    const user = userEvent.setup()
    await user.click(screen.getByTestId('connect-bank-button'))
    await waitFor(() => expect(screen.getByTestId('fake-pluggy-widget')).toBeInTheDocument())
  })

  it('on widget success, posts the item and reports connected', async () => {
    const { fetchMock } = setupFetch()
    const onConnected = renderButton()
    const user = userEvent.setup()

    await user.click(screen.getByTestId('connect-bank-button'))
    await user.click(await screen.findByTestId('fake-pluggy-widget'))

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/bank_connections',
        expect.objectContaining({ method: 'POST' }),
      )
    })
    await waitFor(() => expect(onConnected).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'bc-1' }),
    ))
    expect(screen.getByTestId('connect-bank-feedback')).toHaveTextContent(/banco conectado/i)
  })
})
