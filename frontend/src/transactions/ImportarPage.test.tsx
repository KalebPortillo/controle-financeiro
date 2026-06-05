import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { ImportarPage } from './ImportarPage'

type Handler = { status: number; body: unknown }
function setupFetch(responses: Record<string, Handler | ((init?: RequestInit) => Handler)>) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    const key = `${init?.method ?? 'GET'} ${url}`
    const h = responses[key] ?? responses[url]
    if (!h) throw new Error(`unmocked: ${key}`)
    const { status, body } = typeof h === 'function' ? h(init) : h
    return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return { calls }
}

function imp(o = {}) {
  return {
    id: 'i1', filename: 'extrato.csv', format: 'csv', status: 'completed',
    created_count: 47, duplicate_count: 8, error_count: 1,
    error_log: [{ row: 32, message: 'data inválida' }],
    created_at: '2026-06-05', completed_at: '2026-06-05', ...o,
  }
}

function renderPage() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <ImportarPage />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('<ImportarPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('renders the dropzone and import history', async () => {
    setupFetch({ '/api/v1/imports': { status: 200, body: { imports: [imp()] } } })
    renderPage()
    expect(screen.getByTestId('upload-dropzone')).toBeInTheDocument()
    await waitFor(() => expect(screen.getByTestId('import-row-i1')).toBeInTheDocument())
  })

  it('uploads a file and shows the summary when processing completes', async () => {
    const { calls } = setupFetch({
      '/api/v1/imports': { status: 200, body: { imports: [] } },
      'POST /api/v1/imports': { status: 202, body: { import: imp({ status: 'pending', created_count: 0, duplicate_count: 0, error_count: 0, error_log: [] }) } },
      '/api/v1/imports/i1': { status: 200, body: { import: imp() } },
    })
    renderPage()
    const file = new File(['data,desc,valor\n'], 'extrato.csv', { type: 'text/csv' })
    const input = screen.getByTestId('file-input') as HTMLInputElement
    Object.defineProperty(input, 'files', { value: [file] })
    input.dispatchEvent(new Event('change', { bubbles: true }))

    await waitFor(() => {
      const post = calls.find((c) => c.url === '/api/v1/imports' && c.init?.method === 'POST')
      expect(post).toBeTruthy()
      expect(post!.init!.body).toBeInstanceOf(FormData)
    })
    await waitFor(() => expect(screen.getByTestId('import-summary')).toHaveTextContent('47'))
  })

  it('shows error details on demand', async () => {
    setupFetch({
      '/api/v1/imports': { status: 200, body: { imports: [] } },
      'POST /api/v1/imports': { status: 202, body: { import: imp({ status: 'pending' }) } },
      '/api/v1/imports/i1': { status: 200, body: { import: imp() } },
    })
    renderPage()
    const file = new File(['x'], 'extrato.csv', { type: 'text/csv' })
    const input = screen.getByTestId('file-input') as HTMLInputElement
    Object.defineProperty(input, 'files', { value: [file] })
    input.dispatchEvent(new Event('change', { bubbles: true }))

    const toggle = await screen.findByTestId('toggle-errors')
    toggle.click()
    await waitFor(() => expect(screen.getByTestId('error-details')).toHaveTextContent('Linha 32'))
  })
})
