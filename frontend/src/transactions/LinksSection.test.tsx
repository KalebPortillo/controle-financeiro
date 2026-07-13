import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { LinksSection } from './LinksSection'
import type { InboxTransaction, RelatedItem } from './useInbox'

type Handler = { status: number; body: unknown }
function setupFetch(responses: Record<string, Handler> = {}) {
  const calls: Array<{ url: string; method: string; body: unknown }> = []
  globalThis.fetch = vi.fn(async (url: string, init?: RequestInit) => {
    const method = init?.method ?? 'GET'
    calls.push({ url, method, body: init?.body ? JSON.parse(init.body as string) : undefined })
    const h = responses[`${method} ${url}`] ?? responses[url]
    if (h) return { ok: h.status >= 200 && h.status < 300, status: h.status, json: async () => h.body } as Response
    // Default: qualquer /link_candidates ou /refund_candidates sem override → vazio.
    return { ok: true, status: 200, json: async () => ({ link_candidates: [], refund_candidates: [] }) } as Response
  }) as unknown as typeof fetch
  return { calls }
}

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 't1', account_id: 'a1', account_name: 'Nubank', account_kind: 'credit_card',
    institution_label: 'Nubank', account_institution_name: 'Nubank', account_brand: null,
    account_last_digits: null, card_last_digits: null, installment_number: null, installment_total: null,
    installment_group_id: null, purchase_date: null, foreign_currency: null, direction: 'debit',
    amount_cents: 10000, currency: 'BRL', occurred_at: '2026-06-04', original_description: 'COMPRA',
    improved_title: 'Compra', ai_confidence: null, ai_suggestion: null, ai_status: 'analyzed',
    status: 'pending', source: 'automatic_sync', lock_version: 0, tags: [], effective_amount_cents: 10000,
    refund: null, related: null, ...o,
  }
}

function renderSection(transaction: InboxTransaction) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <LinksSection transaction={transaction} />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

const iofItem: RelatedItem = {
  link_id: 'l1', link_kind: 'link', relation_type: 'iof', role: 'satellite', transaction_id: 'iof1',
  title: 'IOF de compra internacional', direction: 'debit', amount_cents: 228,
  occurred_at: '2026-06-22', status: 'consolidated',
}

const refundItem: RelatedItem = {
  link_id: 'ref1', link_kind: 'refund', relation_type: 'refund', role: 'satellite', origin: 'manual',
  confidence: null, transaction_id: 'cred1', title: 'Estorno loja', direction: 'credit',
  amount_cents: 4000, occurred_at: '2026-06-10', status: 'pending',
}

describe('<LinksSection />', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('lista IOF e estorno juntos, com rótulo e ícone por tipo', () => {
    setupFetch()
    renderSection(tx({ related: [iofItem, refundItem] }))
    expect(screen.getByTestId('link-item-l1')).toHaveTextContent('IOF')
    expect(screen.getByTestId('link-item-ref1')).toHaveTextContent('Estorno')
  })

  it('desvincula estorno via DELETE /transaction_refunds/:id', async () => {
    const { calls } = setupFetch({ 'DELETE /api/v1/transaction_refunds/ref1': { status: 204, body: null } })
    renderSection(tx({ related: [refundItem] }))
    await userEvent.click(screen.getByTestId('link-unlink-ref1'))
    await waitFor(() =>
      expect(calls.some((c) => c.url === '/api/v1/transaction_refunds/ref1' && c.method === 'DELETE')).toBe(true),
    )
  })

  it('desvincula IOF via DELETE /transaction_links/:id', async () => {
    const { calls } = setupFetch({ 'DELETE /api/v1/transaction_links/l1': { status: 204, body: null } })
    renderSection(tx({ related: [iofItem] }))
    await userEvent.click(screen.getByTestId('link-unlink-l1'))
    await waitFor(() =>
      expect(calls.some((c) => c.url === '/api/v1/transaction_links/l1' && c.method === 'DELETE')).toBe(true),
    )
  })

  it('mostra o resumo de efetivo num débito estornado', () => {
    setupFetch()
    renderSection(
      tx({
        direction: 'debit', amount_cents: 10000, effective_amount_cents: 6000, related: [refundItem],
        refund: { refunded_amount_cents: 4000, refunds: [{ id: 'ref1', refund_transaction_id: 'cred1', amount_cents: 4000, confirmed_at: '2026-06-10', origin: 'manual', confidence: null }] },
      }),
    )
    expect(screen.getByTestId('refund-effective')).toHaveTextContent('efetivo')
  })

  it('marca estorno automático de confiança média para conferência', () => {
    setupFetch()
    const auto: RelatedItem = { ...refundItem, link_id: 'ref9', origin: 'automatic', confidence: 'medium' }
    renderSection(tx({ related: [auto] }))
    expect(screen.getByTestId('link-auto-badge-ref9')).toHaveTextContent('confiança média')
  })

  // Crédito não vinculado → picker de estorno (chip Estorno, candidatos de refund).
  it('crédito oferece o fluxo de estorno e vincula por /link_refund', async () => {
    const { calls } = setupFetch({
      '/api/v1/transactions/c1/refund_candidates': {
        status: 200,
        body: { refund_candidates: [{ ...tx({ id: 'd1', direction: 'debit', improved_title: 'Compra loja', amount_cents: 4000 }) }] },
      },
      'POST /api/v1/transactions/c1/link_refund': { status: 201, body: { transaction: tx() } },
    })
    renderSection(tx({ id: 'c1', direction: 'credit', amount_cents: 4000, related: null }))
    await userEvent.click(screen.getByTestId('link-open'))
    const candidate = await screen.findByTestId('link-candidate-d1')
    await userEvent.click(within(candidate).getByText('Compra loja'))
    await waitFor(() => {
      const post = calls.find((c) => c.url === '/api/v1/transactions/c1/link_refund' && c.method === 'POST')
      expect(post?.body).toEqual({ refunded_transaction_id: 'd1' })
    })
  })

  it('crédito NÃO mostra os chips de IOF/tarifa (só estorno)', async () => {
    setupFetch()
    renderSection(tx({ id: 'c1', direction: 'credit', related: null }))
    await userEvent.click(screen.getByTestId('link-open'))
    expect(screen.queryByTestId('link-type-iof')).not.toBeInTheDocument()
  })

  it('débito mostra "Estorno" como primeiro chip, seguido de IOF/tarifa…', async () => {
    setupFetch()
    renderSection(tx({ id: 'd1', direction: 'debit', related: null }))
    await userEvent.click(screen.getByTestId('link-open'))
    const chips = screen.getAllByTestId(/^link-type-/)
    expect(chips[0]).toHaveAttribute('data-testid', 'link-type-refund')
    expect(screen.getByTestId('link-type-fee')).toBeInTheDocument()
    expect(screen.getByTestId('link-type-iof')).toBeInTheDocument()
  })

  it('débito vincula um crédito como estorno via /link_refund (crédito como :id)', async () => {
    const { calls } = setupFetch({
      '/api/v1/transactions/d1/refund_candidates': {
        status: 200,
        body: { refund_candidates: [{ ...tx({ id: 'c9', direction: 'credit', improved_title: 'Estorno loja', amount_cents: 10000 }) }] },
      },
      'POST /api/v1/transactions/c9/link_refund': { status: 201, body: { transaction: tx() } },
    })
    renderSection(tx({ id: 'd1', direction: 'debit', amount_cents: 10000, related: null }))
    await userEvent.click(screen.getByTestId('link-open'))
    // Estorno já vem selecionado (primeiro chip) → lista os créditos candidatos.
    const candidate = await screen.findByTestId('link-candidate-c9')
    await userEvent.click(within(candidate).getByText('Estorno loja'))
    await waitFor(() => {
      const post = calls.find((c) => c.url === '/api/v1/transactions/c9/link_refund' && c.method === 'POST')
      expect(post?.body).toEqual({ refunded_transaction_id: 'd1' })
    })
  })

  it('débito vincula um satélite por /link com o tipo escolhido', async () => {
    const { calls } = setupFetch({
      '/api/v1/transactions/sat1/link_candidates': { status: 200, body: { link_candidates: [{ id: 'orig1', improved_title: 'Assinatura', original_description: 'ASSIN', amount_cents: 5000, occurred_at: '2026-06-01' }] } },
      'POST /api/v1/transactions/sat1/link': { status: 201, body: { transaction: tx() } },
    })
    renderSection(tx({ id: 'sat1', direction: 'debit', related: null }))
    await userEvent.click(screen.getByTestId('link-open'))
    await userEvent.click(screen.getByTestId('link-type-fee'))
    const candidate = await screen.findByTestId('link-candidate-orig1')
    await userEvent.click(candidate)
    await waitFor(() => {
      const post = calls.find((c) => c.url === '/api/v1/transactions/sat1/link' && c.method === 'POST')
      expect(post?.body).toMatchObject({ origin_id: 'orig1', relation_type: 'fee' })
    })
  })

  it('mantém o botão de vincular mesmo quando a transação já tem vínculos', () => {
    setupFetch()
    renderSection(tx({ related: [{ ...iofItem, role: 'origin', transaction_id: 'buy9', title: 'Compra US' }] }))
    expect(screen.getByTestId('link-item-l1')).toHaveTextContent('Origem · Compra US')
    // O botão permanece independente do número de vínculos existentes.
    expect(screen.getByTestId('link-open')).toBeInTheDocument()
  })
})
