import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { InboxBadge } from './InboxBadge'

function setupFetch(pending_count: number) {
  globalThis.fetch = vi.fn().mockImplementation(async (url: string) => {
    if (url.startsWith('/api/v1/transactions')) {
      return { ok: true, status: 200, json: async () => ({ transactions: [], pending_count }) } as Response
    }
    throw new Error(`unmocked: ${url}`)
  }) as unknown as typeof fetch
}

function renderBadge() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <InboxBadge />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<InboxBadge />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('shows the pending count and links to /inbox', async () => {
    setupFetch(4)
    renderBadge()
    const el = await screen.findByTestId('inbox-badge')
    expect(el).toHaveTextContent('4')
    expect(el).toHaveAttribute('href', '/inbox')
  })

  it('renders nothing when there is nothing pending', async () => {
    setupFetch(0)
    const { container } = renderBadge()
    await waitFor(() =>
      expect(container.querySelector('[data-testid="inbox-badge"]')).toBeNull()
    )
  })
})
