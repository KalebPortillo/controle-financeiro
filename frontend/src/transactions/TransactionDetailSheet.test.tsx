import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { TransactionDetailSheet } from './TransactionDetailSheet'
import type { InboxTransaction } from './useInbox'

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 't1', account_id: 'a1', account_name: 'Nubank', account_kind: 'credit_card',
    institution_label: 'Nubank', account_institution_name: 'Nubank', account_brand: null, account_last_digits: null, installment_number: null, installment_total: null,
    installment_group_id: null, direction: 'debit', amount_cents: 10000, currency: 'BRL',
    occurred_at: '2026-06-04', original_description: 'GELADEIRA', improved_title: 'Geladeira',
    ai_confidence: null, ai_suggestion: null, ai_status: 'analyzed', status: 'pending',
    source: 'automatic_sync', lock_version: 0, tags: [], effective_amount_cents: 10000,
    refund: null, ...o,
  }
}

function setupFetch() {
  const calls: Array<{ method: string; url: string; body: unknown }> = []
  globalThis.fetch = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    const method = init?.method ?? 'GET'
    calls.push({ method, url, body: init?.body ? JSON.parse(init.body as string) : undefined })
    let body: unknown = {}
    if (url === '/api/v1/tags') body = { tags: [] }
    else if (url.endsWith('/edits')) body = { edits: [] }
    else if (url.endsWith('/source')) body = { source: 'automatic_sync', source_metadata: { merchant: { businessName: 'VIVO S.A.' } } }
    return { ok: true, status: 200, json: async () => body } as Response
  }) as unknown as typeof fetch
  return calls
}

function renderSheet(transaction: InboxTransaction) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <TransactionDetailSheet transaction={transaction} open onClose={() => {}} mode="inbox" />
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('<TransactionDetailSheet /> parcelamento', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('numa parcela, editar título vai para o endpoint de grupo', async () => {
    const calls = setupFetch()
    renderSheet(tx({ installment_number: 3, installment_total: 12, installment_group_id: 'grp-1' }))

    const input = await screen.findByTestId('sheet-title-t1')
    await userEvent.clear(input)
    await userEvent.type(input, 'Geladeira Brastemp')
    await userEvent.tab() // blur → save

    await waitFor(() => {
      const patch = calls.find((c) => c.method === 'PATCH')
      expect(patch?.url).toBe('/api/v1/installment_groups/grp-1')
      expect((patch?.body as { improved_title: string }).improved_title).toBe('Geladeira Brastemp')
    })
  })

  it('mostra a nota de que título/tags valem para todas as parcelas', async () => {
    setupFetch()
    renderSheet(tx({ installment_number: 1, installment_total: 12, installment_group_id: 'grp-1' }))
    expect(await screen.findByTestId('installment-group-note')).toHaveTextContent('12 parcelas')
  })

  it('numa transação normal, editar título vai para a própria transação', async () => {
    const calls = setupFetch()
    renderSheet(tx())

    const input = await screen.findByTestId('sheet-title-t1')
    await userEvent.clear(input)
    await userEvent.type(input, 'Outro título')
    await userEvent.tab()

    await waitFor(() => {
      const patch = calls.find((c) => c.method === 'PATCH')
      expect(patch?.url).toBe('/api/v1/transactions/t1')
    })
  })

  it('"exibir mais detalhes" busca e mostra o payload do Pluggy', async () => {
    setupFetch()
    renderSheet(tx({ source: 'automatic_sync' }))

    await userEvent.click(await screen.findByTestId('source-toggle-t1'))
    const block = await screen.findByTestId('source-t1')
    expect(block).toHaveTextContent('VIVO S.A.')
  })

  it('gasto manual não mostra "exibir mais detalhes"', async () => {
    setupFetch()
    renderSheet(tx({ source: 'manual_entry' }))
    await screen.findByTestId('sheet-title-t1')
    expect(screen.queryByTestId('source-toggle-t1')).toBeNull()
  })
})
