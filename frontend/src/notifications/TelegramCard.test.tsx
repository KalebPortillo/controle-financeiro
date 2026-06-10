import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { TelegramCard } from './TelegramCard'
import type { TelegramLinkStatus } from './useTelegramLink'

function setupFetch(status: TelegramLinkStatus) {
  const calls: string[] = []
  globalThis.fetch = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    const method = init?.method ?? 'GET'
    calls.push(`${method} ${url}`)
    if (url === '/api/v1/telegram_link' && method === 'GET') {
      return { ok: true, status: 200, json: async () => status } as Response
    }
    if (url === '/api/v1/telegram_link' && method === 'POST') {
      return {
        ok: true, status: 200,
        json: async () => ({
          deep_link: 'https://t.me/test_bot?startgroup=abc123',
          expires_at: '2026-06-10T20:00:00Z',
        }),
      } as Response
    }
    if (url === '/api/v1/telegram_link' && method === 'DELETE') {
      return { ok: true, status: 204, json: async () => ({}) } as Response
    }
    throw new Error(`unmocked: ${method} ${url}`)
  }) as unknown as typeof fetch
  return calls
}

function renderCard() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <TelegramCard />
    </QueryClientProvider>
  )
}

describe('<TelegramCard />', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
    vi.spyOn(window, 'open').mockImplementation(() => null)
  })

  it('desvinculado mostra botão Conectar', async () => {
    setupFetch({ linked: false, chat_title: null, linked_at: null })
    renderCard()
    expect(await screen.findByTestId('telegram-connect')).toHaveTextContent('Conectar Telegram')
  })

  it('conectar gera o link, abre o Telegram e entra em espera', async () => {
    setupFetch({ linked: false, chat_title: null, linked_at: null })
    renderCard()
    await userEvent.click(await screen.findByTestId('telegram-connect'))

    await waitFor(() =>
      expect(window.open).toHaveBeenCalledWith(
        'https://t.me/test_bot?startgroup=abc123', '_blank', 'noopener'
      )
    )
    expect(screen.getByTestId('telegram-waiting')).toBeInTheDocument()
  })

  it('vinculado mostra o grupo e o botão Desvincular', async () => {
    setupFetch({ linked: true, chat_title: 'Casa', linked_at: '2026-06-10T12:00:00Z' })
    renderCard()
    expect(await screen.findByTestId('telegram-status')).toHaveTextContent('Vinculado ao grupo Casa')
    expect(screen.getByTestId('telegram-unlink')).toBeInTheDocument()
  })

  it('desvincular chama DELETE', async () => {
    const calls = setupFetch({ linked: true, chat_title: 'Casa', linked_at: '2026-06-10T12:00:00Z' })
    renderCard()
    await userEvent.click(await screen.findByTestId('telegram-unlink'))

    await waitFor(() => expect(calls).toContain('DELETE /api/v1/telegram_link'))
  })
})
