import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { TagEditor } from './TagEditor'
import type { InboxTag } from './useInbox'

function setupFetch(tags: Array<{ id: string; name: string }>) {
  globalThis.fetch = vi.fn().mockImplementation(async (url: string) => {
    if (url === '/api/v1/tags') {
      return {
        ok: true,
        status: 200,
        json: async () => ({ tags: tags.map((t) => ({ ...t, color: null, icon: null, usage_count: 0 })) }),
      } as Response
    }
    throw new Error(`unmocked: ${url}`)
  }) as unknown as typeof fetch
}

function renderEditor(current: InboxTag[] = [], onChange = vi.fn()) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  render(
    <QueryClientProvider client={qc}>
      <TagEditor transactionId="x" current={current} onChange={onChange} />
    </QueryClientProvider>
  )
  return onChange
}

describe('<TagEditor /> dropdown-search', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('shows all available tags when the empty input is focused', async () => {
    setupFetch([{ id: 'a', name: 'Mercado' }, { id: 'b', name: 'Lazer' }])
    renderEditor()
    const user = userEvent.setup()
    await user.click(screen.getByTestId('tag-input-x'))
    await waitFor(() => expect(screen.getByTestId('tag-dropdown-x')).toBeInTheDocument())
    expect(screen.getByTestId('tag-suggest-a')).toBeInTheDocument()
    expect(screen.getByTestId('tag-suggest-b')).toBeInTheDocument()
  })

  it('typing a substring of an existing tag still offers to create it', async () => {
    setupFetch([{ id: 'a', name: 'Mercado' }])
    renderEditor()
    const user = userEvent.setup()
    await user.type(screen.getByTestId('tag-input-x'), 'merc')
    // a sugestão "Mercado" aparece...
    await waitFor(() => expect(screen.getByTestId('tag-suggest-a')).toBeInTheDocument())
    // ...e o botão criar "merc" também (substring, mas sem match exato)
    expect(screen.getByTestId('tag-create')).toHaveTextContent(/criar "merc"/i)
  })

  it('hides create when an identical tag exists', async () => {
    setupFetch([{ id: 'a', name: 'Mercado' }])
    renderEditor()
    const user = userEvent.setup()
    await user.type(screen.getByTestId('tag-input-x'), 'Mercado')
    await waitFor(() => expect(screen.getByTestId('tag-suggest-a')).toBeInTheDocument())
    expect(screen.queryByTestId('tag-create')).not.toBeInTheDocument()
  })

  it('selecting a suggestion calls onChange with its id', async () => {
    setupFetch([{ id: 'a', name: 'Mercado' }])
    const onChange = renderEditor()
    const user = userEvent.setup()
    await user.click(screen.getByTestId('tag-input-x'))
    await user.click(await screen.findByTestId('tag-suggest-a'))
    expect(onChange).toHaveBeenCalledWith(['a'])
  })
})
