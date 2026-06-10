import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { NotificationsBell } from './NotificationsBell'
import type { AppNotification } from './useNotifications'

function notification(overrides: Partial<AppNotification> = {}): AppNotification {
  return {
    id: 'n1',
    kind: 'sync_failed',
    payload: { institution_label: 'Nubank', error_message: 'Credenciais expiradas' },
    read_at: null,
    created_at: new Date().toISOString(),
    ...overrides,
  }
}

function setupFetch(notifications: AppNotification[], unread = notifications.filter((n) => !n.read_at).length) {
  const calls: string[] = []
  globalThis.fetch = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push(`${init?.method ?? 'GET'} ${url}`)
    if (url === '/api/v1/notifications' && (init?.method ?? 'GET') === 'GET') {
      return {
        ok: true, status: 200,
        json: async () => ({ notifications, unread_count: unread }),
      } as Response
    }
    if (url.endsWith('/mark_read') || url.endsWith('/mark_all_read')) {
      return { ok: true, status: 200, json: async () => ({}) } as Response
    }
    throw new Error(`unmocked: ${url}`)
  }) as unknown as typeof fetch
  return calls
}

function renderBell() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <NotificationsBell />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<NotificationsBell />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('mostra badge com a contagem de não lidas', async () => {
    setupFetch([notification(), notification({ id: 'n2', read_at: '2026-06-10T10:00:00Z' })])
    renderBell()
    await waitFor(() =>
      expect(screen.getByTestId('notifications-badge')).toHaveTextContent('1')
    )
  })

  it('sem não lidas não mostra badge', async () => {
    setupFetch([notification({ read_at: '2026-06-10T10:00:00Z' })])
    renderBell()
    await waitFor(() => expect(screen.getByTestId('notifications-bell')).toBeInTheDocument())
    expect(screen.queryByTestId('notifications-badge')).toBeNull()
  })

  it('clique abre o painel com os itens e título PT-BR', async () => {
    setupFetch([notification()])
    renderBell()
    await userEvent.click(await screen.findByTestId('notifications-bell'))

    expect(screen.getByText('Notificações')).toBeInTheDocument()
    expect(screen.getByText('Falha na sincronização do Nubank')).toBeInTheDocument()
    expect(screen.getByText('Credenciais expiradas')).toBeInTheDocument()
    expect(screen.getByTestId('unread-dot')).toBeInTheDocument()
  })

  it('painel vazio mostra empty state', async () => {
    setupFetch([])
    renderBell()
    await userEvent.click(await screen.findByTestId('notifications-bell'))
    expect(screen.getByText('Nenhuma notificação')).toBeInTheDocument()
  })

  it('clicar num item não lido chama mark_read', async () => {
    const calls = setupFetch([notification()])
    renderBell()
    await userEvent.click(await screen.findByTestId('notifications-bell'))
    await userEvent.click(screen.getByTestId('notification-item'))

    await waitFor(() =>
      expect(calls).toContain('POST /api/v1/notifications/n1/mark_read')
    )
  })

  it('"Marcar todas como lidas" chama mark_all_read', async () => {
    const calls = setupFetch([notification()])
    renderBell()
    await userEvent.click(await screen.findByTestId('notifications-bell'))
    await userEvent.click(screen.getByTestId('mark-all-read'))

    await waitFor(() =>
      expect(calls).toContain('POST /api/v1/notifications/mark_all_read')
    )
  })

  it('títulos por kind: inbox_new e recurrent_missed', async () => {
    setupFetch([
      notification({ id: 'a', kind: 'inbox_new', payload: { count: 3 } }),
      notification({
        id: 'b', kind: 'recurrent_missed',
        payload: { descriptor_pattern: 'NETFLIX', days_overdue: 5 },
      }),
    ])
    renderBell()
    await userEvent.click(await screen.findByTestId('notifications-bell'))

    expect(screen.getByText('3 novos gastos na inbox')).toBeInTheDocument()
    expect(screen.getByText('Recorrente atrasada: NETFLIX')).toBeInTheDocument()
    expect(screen.getByText('5 dias de atraso')).toBeInTheDocument()
  })
})
