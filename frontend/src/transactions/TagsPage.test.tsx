import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { TagsPage } from './TagsPage'
import type { Tag } from './useTags'

type MockResponse = { status: number; body: unknown }

type Handler = MockResponse | ((init?: RequestInit) => MockResponse)

function setupFetch(responses: Record<string, Handler>) {
  // Default: suggested_tags vazio, pra não precisar declarar em todo teste.
  const withDefaults: Record<string, Handler> = {
    '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [] } },
    ...responses,
  }
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const handler = withDefaults[`${init?.method ?? 'GET'} ${url}`] ?? withDefaults[url]
    if (!handler) throw new Error(`unmocked: ${init?.method ?? 'GET'} ${url}`)
    const { status, body } = typeof handler === 'function' ? handler(init) : handler
    return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { fetchMock }
}

function tag(o: Partial<Tag> = {}): Tag {
  return { id: 't1', name: 'Mercado', color: null, icon: null, usage_count: 0, ...o }
}

function renderTags() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <TagsPage />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<TagsPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists tags with usage count', async () => {
    setupFetch({ '/api/v1/tags': { status: 200, body: { tags: [tag({ usage_count: 3 })] } } })
    renderTags()
    await waitFor(() => expect(screen.getByTestId('tag-row-t1')).toBeInTheDocument())
    expect(screen.getByText(/3 usos/)).toBeInTheDocument()
  })

  it('creates a tag', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      'POST /api/v1/tags': { status: 201, body: { tag: tag({ name: 'Lazer' }) } },
    })
    renderTags()
    const user = userEvent.setup()
    await user.type(screen.getByTestId('new-tag-name'), 'Lazer')
    await user.click(screen.getByTestId('new-tag-submit'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith('/api/v1/tags', expect.objectContaining({ method: 'POST' }))
    )
  })

  it('edits name + color', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/tags': { status: 200, body: { tags: [tag()] } },
      'PATCH /api/v1/tags/t1': { status: 200, body: { tag: tag({ name: 'Supermercado', color: '#15803D' }) } },
    })
    renderTags()
    const user = userEvent.setup()
    const row = await screen.findByTestId('tag-row-t1')
    await user.click(within(row).getByTestId('tag-edit-t1'))
    await user.click(within(row).getByTestId('swatch-t1-#15803D'))
    await user.click(within(row).getByTestId('tag-save-t1'))
    await waitFor(() => {
      const call = fetchMock.mock.calls.find((c) => c[0] === '/api/v1/tags/t1' && c[1]?.method === 'PATCH')
      expect(JSON.parse(call![1]!.body as string).color).toBe('#15803D')
    })
  })

  it('shows a friendly message when deleting a tag in use (422)', async () => {
    setupFetch({
      'GET /api/v1/tags': { status: 200, body: { tags: [tag()] } },
      'DELETE /api/v1/tags/t1': { status: 422, body: { error: { code: 'tag_in_use', message: 'in use' } } },
    })
    renderTags()
    const user = userEvent.setup()
    const row = await screen.findByTestId('tag-row-t1')
    await user.click(within(row).getByTestId('tag-delete-t1'))
    await waitFor(() => expect(within(row).getByRole('alert')).toHaveTextContent(/mesclar/i))
  })
})

const suggestion = {
  id: 's1', name: 'Delivery', rationale: '5 pedidos no iFood',
  coverage: 5, source: 'detected', status: 'pending',
}

describe('<TagsPage /> — tags sugeridas pela IA (F3)', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists AI suggestions in a separate section', async () => {
    setupFetch({
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [suggestion] } },
    })
    renderTags()
    await waitFor(() => expect(screen.getByTestId('suggested-tag-s1')).toBeInTheDocument())
    expect(screen.getByText('Delivery')).toBeInTheDocument()
    expect(screen.getByText(/5 pedidos no iFood/)).toBeInTheDocument()
  })

  it('accepts a suggestion (POST accept)', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [suggestion] } },
      'POST /api/v1/suggested_tags/s1/accept': { status: 200, body: { tag: tag({ name: 'Delivery' }) } },
    })
    renderTags()
    const user = userEvent.setup()
    const row = await screen.findByTestId('suggested-tag-s1')
    await user.click(within(row).getByTestId('accept-suggestion-s1'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/suggested_tags/s1/accept',
        expect.objectContaining({ method: 'POST' }),
      )
    )
  })

  it('dismisses a suggestion (DELETE)', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      '/api/v1/suggested_tags': { status: 200, body: { suggested_tags: [suggestion] } },
      'DELETE /api/v1/suggested_tags/s1': { status: 204, body: null },
    })
    renderTags()
    const user = userEvent.setup()
    const row = await screen.findByTestId('suggested-tag-s1')
    await user.click(within(row).getByTestId('dismiss-suggestion-s1'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/suggested_tags/s1',
        expect.objectContaining({ method: 'DELETE' }),
      )
    )
  })

  it('hides the suggestions section when there are none', async () => {
    setupFetch({ 'GET /api/v1/tags': { status: 200, body: { tags: [tag()] } } })
    renderTags()
    await screen.findByTestId('tag-row-t1')
    expect(screen.queryByTestId('suggested-section')).not.toBeInTheDocument()
  })
})
