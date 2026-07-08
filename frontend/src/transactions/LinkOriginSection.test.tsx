import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { LinkOriginSection } from './LinkOriginSection'
import type { InboxTransaction, RelatedItem } from './useInbox'

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 'sat1', account_id: 'a1', account_name: 'Nubank', account_kind: 'credit_card',
    institution_label: 'Nubank', account_institution_name: 'Nubank', account_brand: null,
    account_last_digits: null, card_last_digits: null, installment_number: null, installment_total: null,
    installment_group_id: null, purchase_date: null, foreign_currency: null, direction: 'debit', amount_cents: 120, currency: 'BRL',
    occurred_at: '2026-06-05', original_description: 'TARIFA', improved_title: null,
    ai_confidence: null, ai_suggestion: null, ai_status: 'analyzed', status: 'pending',
    source: 'automatic_sync', lock_version: 0, tags: [], effective_amount_cents: 120,
    refund: null, related: null, ...o,
  }
}

function rel(o: Partial<RelatedItem> & Pick<RelatedItem, 'role' | 'transaction_id'>): RelatedItem {
  return {
    link_id: 'l1', relation_type: 'iof', title: 'X', direction: 'debit',
    amount_cents: 0, occurred_at: '2026-06-04', status: 'pending', ...o,
  }
}

const candidate = { id: 'orig1', improved_title: 'Assinatura', original_description: 'ASSIN',
  amount_cents: 5000, occurred_at: '2026-06-01' }

let fetchMock: ReturnType<typeof vi.fn>
beforeEach(() => {
  fetchMock = vi.fn((url: string, opts?: RequestInit) => {
    if (String(url).includes('/link_candidates')) {
      return Promise.resolve({ ok: true, status: 200, json: async () => ({ link_candidates: [candidate] }) } as Response)
    }
    if (String(url).includes('/link') && opts?.method === 'POST') {
      return Promise.resolve({ ok: true, status: 201, json: async () => ({ transaction: tx() }) } as Response)
    }
    return Promise.resolve({ ok: true, status: 200, json: async () => ({}) } as Response)
  })
  globalThis.fetch = fetchMock as unknown as typeof fetch
})

function renderSection(t: InboxTransaction) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <LinkOriginSection transaction={t} />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('LinkOriginSection', () => {
  it('não aparece quando a transação já tem uma origem', () => {
    renderSection(tx({ related: [rel({ role: 'origin', transaction_id: 'orig1' })] }))
    expect(screen.queryByTestId('link-origin-section')).not.toBeInTheDocument()
  })

  it('abre o picker, lista candidatos e vincula com o tipo escolhido', async () => {
    renderSection(tx())
    await userEvent.click(screen.getByTestId('link-origin-open'))
    await userEvent.click(screen.getByTestId('link-type-fee'))

    const candidateBtn = await screen.findByTestId('link-candidate-orig1')
    await userEvent.click(candidateBtn)

    await waitFor(() => {
      const post = fetchMock.mock.calls.find(
        ([url, opts]) => String(url).includes('/transactions/sat1/link') && (opts as RequestInit)?.method === 'POST',
      )
      expect(post).toBeTruthy()
      expect(JSON.parse((post![1] as RequestInit).body as string)).toMatchObject({
        origin_id: 'orig1', relation_type: 'fee',
      })
    })
  })
})
