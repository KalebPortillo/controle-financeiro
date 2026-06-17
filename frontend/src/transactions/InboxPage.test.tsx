import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { InboxPage } from './InboxPage'
import type { InboxTransaction } from './useInbox'

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
  return { fetchMock, calls }
}

function tx(overrides: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 't1',
    account_id: 'a1',
    account_name: 'Nubank CC',
    account_kind: 'credit_card',
    institution_label: 'Nubank',
    account_institution_name: 'Nubank',
    account_brand: null,
    account_last_digits: null, card_last_digits: null,
    installment_number: null,
    installment_total: null,
    installment_group_id: null,
    purchase_date: null,
    direction: 'debit',
    amount_cents: 2500,
    currency: 'BRL',
    occurred_at: '2026-05-20',
    original_description: 'PADARIA CENTRAL',
    improved_title: null,
    ai_confidence: null,
    ai_suggestion: null,
    ai_status: 'analyzed',
    status: 'pending',
    source: 'automatic_sync',
    lock_version: 0,
    tags: [],
    effective_amount_cents: 2500,
    refund: null,
    ...overrides,
  }
}

function renderInbox() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <InboxPage />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<InboxPage />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lists pending transactions in the table', async () => {
    setupFetch({
      '/api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx()], pending_count: 1 },
      },
    })
    renderInbox()
    await waitFor(() => expect(screen.getByText('PADARIA CENTRAL')).toBeInTheDocument())
    expect(screen.getByTestId('inbox-row-t1')).toBeInTheDocument()
  })

  it('shows the original bank description when the AI changed the title', async () => {
    setupFetch({
      '/api/v1/transactions?status=pending': {
        status: 200,
        body: {
          transactions: [tx({ improved_title: 'Padaria', original_description: 'PADARIA CENTRAL-2378' })],
          pending_count: 1,
        },
      },
    })
    renderInbox()
    const orig = await screen.findByTestId('original-t1')
    expect(orig).toHaveTextContent('PADARIA CENTRAL-2378')
  })

  it('does not show the original line when the title equals the original', async () => {
    setupFetch({
      '/api/v1/transactions?status=pending': {
        status: 200,
        body: {
          transactions: [tx({ improved_title: 'PADARIA CENTRAL', original_description: 'PADARIA CENTRAL' })],
          pending_count: 1,
        },
      },
    })
    renderInbox()
    await screen.findByTestId('inbox-row-t1')
    expect(screen.queryByTestId('original-t1')).not.toBeInTheDocument()
  })

  it('reverts the title to the original via the detail sheet', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: {
          transactions: [tx({ improved_title: 'Padaria', original_description: 'PADARIA CENTRAL-2378' })],
          pending_count: 1,
        },
      },
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      'PATCH /api/v1/transactions/t1': { status: 200, body: { transaction: tx() } },
    })
    renderInbox()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('inbox-row-t1'))
    await user.click(await screen.findByTestId('sheet-use-original-t1'))
    await waitFor(() => {
      const call = fetchMock.mock.calls.find((c) => c[0] === '/api/v1/transactions/t1' && c[1]?.method === 'PATCH')
      expect(call).toBeTruthy()
      expect(JSON.parse(call![1]!.body as string).improved_title).toBe('PADARIA CENTRAL-2378')
    })
  })

  it('shows an empty state when nothing is pending', async () => {
    setupFetch({
      '/api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [], pending_count: 0 },
      },
    })
    renderInbox()
    await waitFor(() => expect(screen.getByTestId('inbox-empty')).toBeInTheDocument())
  })

  it('opens the detail sheet on row click and accepts via consolidate', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx()], pending_count: 1 },
      },
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      'POST /api/v1/transactions/t1/consolidate': { status: 200, body: { transaction: tx({ status: 'consolidated' }) } },
    })
    renderInbox()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('inbox-row-t1'))
    await user.click(await screen.findByTestId('sheet-accept-t1'))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/transactions/t1/consolidate',
        expect.objectContaining({ method: 'POST' })
      )
    )
  })

  it('edits the title in the sheet and PATCHes with lock_version on blur', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx({ lock_version: 4 })], pending_count: 1 },
      },
      'GET /api/v1/tags': { status: 200, body: { tags: [] } },
      'PATCH /api/v1/transactions/t1': { status: 200, body: { transaction: tx() } },
    })
    renderInbox()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('inbox-row-t1'))
    const title = await screen.findByTestId('sheet-title-t1')
    await user.clear(title)
    await user.type(title, 'Almoço')
    await user.tab() // blur

    await waitFor(() => {
      const call = fetchMock.mock.calls.find(
        (c) => c[0] === '/api/v1/transactions/t1' && c[1]?.method === 'PATCH'
      )
      expect(call).toBeTruthy()
      const body = JSON.parse(call![1]!.body as string)
      expect(body.lock_version).toBe(4)
      expect(body.improved_title).toBe('Almoço')
    })
  })

  it('swiping a row left accepts it (consolidate), without opening the sheet', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx()], pending_count: 1 },
      },
      'POST /api/v1/transactions/t1/consolidate': { status: 200, body: { transaction: tx() } },
    })
    renderInbox()
    const row = await screen.findByTestId('inbox-row-t1')
    // arrasta pra esquerda além do limiar e solta
    fireEvent.pointerDown(row, { clientX: 240, pointerId: 1 })
    fireEvent.pointerMove(row, { clientX: 100, pointerId: 1 })
    fireEvent.pointerUp(row, { clientX: 100, pointerId: 1 })

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/transactions/t1/consolidate',
        expect.objectContaining({ method: 'POST' })
      )
    )
    expect(screen.queryByTestId('sheet-accept-t1')).not.toBeInTheDocument()
  })

  it('swiping a row right selects it (shows the bulk action bar)', async () => {
    setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx()], pending_count: 1 },
      },
    })
    renderInbox()
    const row = await screen.findByTestId('inbox-row-t1')
    fireEvent.pointerDown(row, { clientX: 100, pointerId: 1 })
    fireEvent.pointerMove(row, { clientX: 240, pointerId: 1 })
    fireEvent.pointerUp(row, { clientX: 240, pointerId: 1 })

    // selecionou → barra de ações em massa aparece
    await waitFor(() => expect(screen.getByTestId('bulk-accept')).toBeInTheDocument())
  })

  it('bulk-accepts selected rows in a single bulk request', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx({ id: 't1' }), tx({ id: 't2' })], pending_count: 2 },
      },
      'POST /api/v1/transactions/bulk_consolidate': { status: 200, body: { count: 2 } },
    })
    renderInbox()
    const user = userEvent.setup()
    await user.click(await screen.findByTestId('select-t1'))
    await user.click(await screen.findByTestId('select-t2'))
    await user.click(await screen.findByTestId('bulk-accept'))

    await waitFor(() => {
      const call = fetchMock.mock.calls.find(
        (c) => c[0] === '/api/v1/transactions/bulk_consolidate' && c[1]?.method === 'POST'
      )
      expect(call).toBeTruthy()
      expect((JSON.parse(call![1]!.body as string).ids as string[]).sort()).toEqual(['t1', 't2'])
    })
    // um único request, não um por item
    expect(
      fetchMock.mock.calls.filter((c) => String(c[0]).includes('consolidate')).length
    ).toBe(1)
  })

  it('shows a real analysis progress bar while transactions are being analyzed', async () => {
    setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx({ id: 't1' }), tx({ id: 't2' })], pending_count: 2 },
      },
      'GET /api/v1/transactions/analysis_progress': {
        status: 200,
        body: { total: 4, analyzed: 1, failed: 0, awaiting: 3, done: false, error: null },
      },
    })
    renderInbox()

    const progress = await screen.findByTestId('analysis-progress')
    expect(progress).toHaveTextContent('1 de 4')
    expect(progress).toHaveTextContent('25%')
    expect(screen.getByTestId('reanalyze-btn')).toHaveTextContent('Analisando… 1/4')
  })

  it('hides the progress bar when analysis is done', async () => {
    setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx({ id: 't1' })], pending_count: 1 },
      },
      'GET /api/v1/transactions/analysis_progress': {
        status: 200,
        body: { total: 1, analyzed: 1, failed: 0, awaiting: 0, done: true, error: null },
      },
    })
    renderInbox()
    await screen.findByTestId('inbox-row-t1')
    expect(screen.queryByTestId('analysis-progress')).not.toBeInTheDocument()
    expect(screen.getByTestId('reanalyze-btn')).toHaveTextContent('Reanalisar com IA')
  })

  it('shows a "não analisados" banner (not the progress bar) when some failed and none await', async () => {
    setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx({ id: 't1' })], pending_count: 1 },
      },
      'GET /api/v1/transactions/analysis_progress': {
        status: 200,
        body: {
          total: 4, analyzed: 1, failed: 3, awaiting: 0, done: true,
          error: { reason: 'quota', message: 'O limite do serviço de IA foi atingido.', at: '2026-06-05T00:00:00Z' },
        },
      },
    })
    renderInbox()

    const banner = await screen.findByTestId('ai-failed-banner')
    expect(banner).toHaveTextContent(/3 gastos não foram analisados/i)
    expect(banner).toHaveTextContent(/limite do serviço de IA/i)
    expect(screen.queryByTestId('analysis-progress')).not.toBeInTheDocument()
  })

  it('a failed transaction shows a "não analisado" badge in its row', async () => {
    setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx({ id: 't1', ai_status: 'failed' })], pending_count: 1 },
      },
      'GET /api/v1/transactions/analysis_progress': {
        status: 200,
        body: { total: 1, analyzed: 0, failed: 1, awaiting: 0, done: true, error: null },
      },
    })
    renderInbox()
    expect(await screen.findByTestId('not-analyzed-t1')).toHaveTextContent(/não analisado/i)
  })

  it('retrying from the failed banner posts to reanalyze', async () => {
    const { fetchMock } = setupFetch({
      'GET /api/v1/transactions?status=pending': {
        status: 200,
        body: { transactions: [tx({ id: 't1' })], pending_count: 1 },
      },
      'GET /api/v1/transactions/analysis_progress': {
        status: 200,
        body: { total: 4, analyzed: 1, failed: 3, awaiting: 0, done: true, error: { reason: 'quota', message: 'Limite.', at: 'x' } },
      },
      'POST /api/v1/transactions/reanalyze': { status: 202, body: { enqueued: true, pending_count: 4 } },
    })
    renderInbox()

    const user = userEvent.setup()
    await user.click(await screen.findByTestId('ai-error-retry'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/transactions/reanalyze',
        expect.objectContaining({ method: 'POST' })
      )
    )
  })

  function parcels() {
    return [
      tx({ id: 'p1', improved_title: 'Geladeira', installment_number: 1, installment_total: 12,
           installment_group_id: 'g1', amount_cents: 10000, occurred_at: '2026-03-10' }),
      tx({ id: 'p2', improved_title: 'Geladeira', installment_number: 2, installment_total: 12,
           installment_group_id: 'g1', amount_cents: 10000, occurred_at: '2026-04-10' }),
    ]
  }

  it('agrega as parcelas num item único com o valor total somado', async () => {
    setupFetch({
      '/api/v1/transactions?status=pending': { status: 200, body: { transactions: parcels(), pending_count: 2 } },
    })
    renderInbox()

    await waitFor(() => expect(screen.getByTestId('inbox-group-g1')).toBeInTheDocument())
    // total = 100 + 100 = R$ 200,00 (uma linha só, não duas)
    expect(screen.getByTestId('group-total-g1')).toHaveTextContent('200,00')
    expect(screen.getAllByText('Geladeira')).toHaveLength(1)
    // a lista de parcelas vive no sheet (fechado até clicar)
    expect(screen.queryByTestId('group-sheet-parcels-g1')).toBeNull()
  })

  it('clicar no parcelamento abre o sheet com a lista das parcelas', async () => {
    setupFetch({
      '/api/v1/transactions?status=pending': { status: 200, body: { transactions: parcels(), pending_count: 2 } },
    })
    renderInbox()

    await userEvent.click(await screen.findByTestId('inbox-group-g1'))
    expect(await screen.findByTestId('group-sheet-parcels-g1')).toBeInTheDocument()
    expect(screen.getByTestId('group-sheet-parcel-p1')).toHaveTextContent('1/12')
    expect(screen.getByTestId('group-sheet-parcel-p2')).toHaveTextContent('2/12')
    // rodapé de ação em grupo
    expect(screen.getByTestId('group-sheet-accept-g1')).toHaveTextContent('Aceitar todas (2)')
  })

  it('aceitar todas pelo sheet chama o endpoint de grupo', async () => {
    const { fetchMock } = setupFetch({
      '/api/v1/transactions?status=pending': { status: 200, body: { transactions: parcels(), pending_count: 2 } },
      'POST /api/v1/installment_groups/g1/consolidate': { status: 200, body: { count: 2 } },
    })
    renderInbox()

    await userEvent.click(await screen.findByTestId('inbox-group-g1'))
    await userEvent.click(await screen.findByTestId('group-sheet-accept-g1'))
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/installment_groups/g1/consolidate',
        expect.objectContaining({ method: 'POST' })
      )
    )
  })

  it('selecionar o parcelamento marca todas as parcelas (barra de ações em massa)', async () => {
    setupFetch({
      '/api/v1/transactions?status=pending': { status: 200, body: { transactions: parcels(), pending_count: 2 } },
    })
    renderInbox()

    await userEvent.click(await screen.findByTestId('select-group-g1'))
    expect(screen.getByTestId('bulk-accept')).toHaveTextContent('Aceitar (2)')
  })

  it('abrir uma parcela a partir do grupo mostra "← Parcelamento" e o back volta pro grupo', async () => {
    setupFetch({
      '/api/v1/transactions?status=pending': { status: 200, body: { transactions: parcels(), pending_count: 2 } },
      '/api/v1/tags': { status: 200, body: { tags: [] } },
    })
    const user = userEvent.setup()
    renderInbox()

    // grupo → parcela
    await user.click(await screen.findByTestId('inbox-group-g1'))
    await user.click(await screen.findByTestId('group-sheet-parcel-p1'))

    // detalhe da parcela aberto, com o back pro grupo; a lista do grupo some
    const back = await screen.findByTestId('back-to-group')
    expect(screen.queryByTestId('group-sheet-parcels-g1')).toBeNull()

    // "← Parcelamento" (= back do navegador) restaura o sheet do grupo
    await user.click(back)
    expect(await screen.findByTestId('group-sheet-parcels-g1')).toBeInTheDocument()
    expect(screen.queryByTestId('back-to-group')).toBeNull()
  })
})
