import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { GhostTagChips } from './GhostTagChips'
import type { SuggestedTag } from './useSuggestedTags'

type MockResponse = { status: number; body: unknown }

function setupFetch(responses: Record<string, MockResponse>) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const handler = responses[`${init?.method ?? 'GET'} ${url}`] ?? responses[url]
    if (!handler) throw new Error(`unmocked: ${init?.method ?? 'GET'} ${url}`)
    return { ok: handler.status >= 200 && handler.status < 300, status: handler.status, json: async () => handler.body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { calls, fetchMock }
}

function suggestion(o: Partial<SuggestedTag> = {}): SuggestedTag {
  return { id: 's1', name: 'Delivery', rationale: null, coverage: 3, source: 'inbox', status: 'pending', ...o }
}

function renderChips(props: { transactionId: string; suggestedNames: string[] }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <GhostTagChips {...props} />
    </QueryClientProvider>,
  )
}

describe('<GhostTagChips />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders a ghost chip for a suggested name that is pending in the catalog', async () => {
    setupFetch({ '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [suggestion()] } } })
    renderChips({ transactionId: 'tx-1', suggestedNames: ['Delivery'] })
    await waitFor(() => expect(screen.getByTestId('ghost-chip-s1')).toHaveTextContent('Delivery'))
  })

  it('does not render chips for names not in the pending catalog', async () => {
    setupFetch({ '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [] } } })
    renderChips({ transactionId: 'tx-1', suggestedNames: ['Delivery'] })
    await waitFor(() => expect(screen.queryByTestId('ghost-chip-s1')).not.toBeInTheDocument())
  })

  it('clicking a ghost chip accepts it and applies to the transaction', async () => {
    const { calls } = setupFetch({
      '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [suggestion()] } },
      'POST /api/v1/suggested_tags/s1/accept': { status: 200, body: { tag: { id: 't9', name: 'Delivery', color: null, icon: null } } },
    })
    renderChips({ transactionId: 'tx-1', suggestedNames: ['Delivery'] })
    const chip = await screen.findByTestId('ghost-chip-s1')
    const user = userEvent.setup()
    await user.click(chip)
    await waitFor(() => {
      const post = calls.find((c) => c.url === '/api/v1/suggested_tags/s1/accept' && c.init?.method === 'POST')
      expect(post).toBeTruthy()
      expect(JSON.parse(post!.init!.body as string)).toEqual({ transaction_id: 'tx-1' })
    })
  })

  it('renders nothing when there are no suggested names', () => {
    setupFetch({ '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [suggestion()] } } })
    const { container } = renderChips({ transactionId: 'tx-1', suggestedNames: [] })
    expect(container).toBeEmptyDOMElement()
  })
})
