import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { CategoriasPage } from './CategoriasPage'
import type { Category } from './useCategories'

type MockResponse = { status: number; body: unknown }

function setupFetch(
  responses: Record<string, MockResponse | ((init?: RequestInit) => MockResponse)>
) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const handler = responses[`${init?.method ?? 'GET'} ${url}`] ?? responses[url]
    if (!handler) throw new Error(`unmocked: ${init?.method ?? 'GET'} ${url}`)
    const { status, body } = typeof handler === 'function' ? handler(init) : handler
    return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { fetchMock }
}

function cat(o: Partial<Category> = {}): Category {
  return { id: 'c1', name: 'Alimentação', color: null, icon: null, tags: [], tag_suggestions: [], ...o }
}

function renderCategorias() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <CategoriasPage />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<CategoriasPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists categories with their tags', async () => {
    setupFetch({
      '/api/v1/categories': {
        status: 200,
        body: { categories: [cat({ tags: [{ id: 't1', name: 'Padaria', color: null, icon: null }] })] },
      },
    })
    renderCategorias()
    await waitFor(() => expect(screen.getByTestId('category-row-c1')).toBeInTheDocument())
    expect(screen.getByText('Alimentação')).toBeInTheDocument()
    expect(screen.getByText('Padaria')).toBeInTheDocument()
  })

  it('creates a category', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/categories': { status: 200, body: { categories: [] } },
      'POST /api/v1/categories': { status: 201, body: { category: cat({ name: 'Casa' }) } },
    })
    renderCategorias()
    const user = userEvent.setup()
    await user.type(screen.getByTestId('new-category-name'), 'Casa')
    await user.click(screen.getByTestId('new-category-submit'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith('/api/v1/categories', expect.objectContaining({ method: 'POST' }))
    )
  })

  it('edits name + color + tags', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/categories': { status: 200, body: { categories: [cat()] } },
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      'PATCH /api/v1/categories/c1': { status: 200, body: { category: cat({ name: 'Lar' }) } },
    })
    renderCategorias()
    const user = userEvent.setup()
    const row = await screen.findByTestId('category-row-c1')
    await user.click(within(row).getByTestId('category-edit-c1'))
    await user.click(within(row).getByTestId('cat-swatch-c1-#15803D'))
    await user.click(within(row).getByTestId('category-save-c1'))
    await waitFor(() => {
      const call = fetchMock.mock.calls.find((c) => c[0] === '/api/v1/categories/c1' && c[1]?.method === 'PATCH')
      expect(JSON.parse(call![1]!.body as string).color).toBe('#15803D')
    })
  })

  it('deletes a category', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/categories': { status: 200, body: { categories: [cat()] } },
      'DELETE /api/v1/categories/c1': { status: 204, body: null },
    })
    renderCategorias()
    const user = userEvent.setup()
    const row = await screen.findByTestId('category-row-c1')
    await user.click(within(row).getByTestId('category-delete-c1'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith('/api/v1/categories/c1', expect.objectContaining({ method: 'DELETE' }))
    )
  })

  // --- Categorias sugeridas (B-fe) ---

  it('suggesting categories posts to generate', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/categories': { status: 200, body: { categories: [] } },
      'GET /api/v1/suggested_categories': { status: 200, body: { suggested_categories: [], ai_error: null } },
      'POST /api/v1/suggested_categories/generate': { status: 202, body: null },
    })
    renderCategorias()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('suggest-categories-btn'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/suggested_categories/generate',
        expect.objectContaining({ method: 'POST' })
      )
    )
  })

  it('renders suggested categories with their tags', async () => {
    setupFetch({
      'GET /api/v1/categories': { status: 200, body: { categories: [] } },
      'GET /api/v1/suggested_categories': {
        status: 200,
        body: {
          suggested_categories: [{ id: 's1', name: 'Essenciais', tag_names: ['Mercado', 'Contas'], status: 'pending' }],
          ai_error: null,
        },
      },
    })
    renderCategorias()
    expect(await screen.findByText('Essenciais')).toBeInTheDocument()
    expect(screen.getByTestId('accept-suggested-category-s1')).toBeInTheDocument()
  })

  it('shows a friendly Alert when AI category suggestion failed', async () => {
    setupFetch({
      'GET /api/v1/categories': { status: 200, body: { categories: [] } },
      'GET /api/v1/suggested_categories': {
        status: 200,
        body: {
          suggested_categories: [],
          ai_error: { reason: 'quota', message: 'O limite do serviço de IA foi atingido.', at: 'x' },
        },
      },
    })
    renderCategorias()
    const banner = await screen.findByTestId('suggested-categories-error')
    expect(banner).toHaveTextContent(/limite do serviço de IA/i)
    expect(screen.getByTestId('suggest-categories-retry')).toBeInTheDocument()
  })

  // --- Tags sugeridas por categoria (C-fe) ---

  it('suggesting tags for a category posts to suggest_tags', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/categories': { status: 200, body: { categories: [cat()], ai_error: null } },
      'POST /api/v1/categories/c1/suggest_tags': { status: 202, body: null },
    })
    renderCategorias()
    const user = userEvent.setup()
    const row = await screen.findByTestId('category-row-c1')
    await user.click(within(row).getByTestId('category-suggest-tags-c1'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/categories/c1/suggest_tags',
        expect.objectContaining({ method: 'POST' })
      )
    )
  })

  it('renders suggested tags and accepting one posts the accept', async () => {
    const withSug = cat({ tag_suggestions: [{ id: 't9', name: 'Luz', color: null, icon: null }] })
    const { fetchMock } = setupFetch({
      'GET /api/v1/categories': { status: 200, body: { categories: [withSug], ai_error: null } },
      'POST /api/v1/categories/c1/tag_suggestions/t9/accept': { status: 200, body: { category: cat() } },
    })
    renderCategorias()
    const user = userEvent.setup()
    expect(await screen.findByTestId('tag-suggestion-c1-t9')).toHaveTextContent('Luz')
    await user.click(screen.getByTestId('accept-tag-suggestion-c1-t9'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/categories/c1/tag_suggestions/t9/accept',
        expect.objectContaining({ method: 'POST' })
      )
    )
  })
})
