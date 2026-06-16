import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { InstallmentGroupSheet } from './InstallmentGroupSheet'
import type { InboxTransaction } from './useInbox'
import type { InboxItem } from './inboxItems'

type InstallmentItem = Extract<InboxItem, { kind: 'installment' }>

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 't1', account_id: 'a1', account_name: 'Nubank', account_kind: 'credit_card',
    institution_label: 'Nubank', account_institution_name: 'Nubank', account_brand: null,
    account_last_digits: null, card_last_digits: null, installment_number: 1, installment_total: 3,
    installment_group_id: 'g1', direction: 'debit', amount_cents: 10000, currency: 'BRL',
    occurred_at: '2026-06-04', original_description: 'GELADEIRA 01/03', improved_title: 'Geladeira',
    ai_confidence: null, ai_suggestion: null, ai_status: 'analyzed', status: 'pending',
    source: 'automatic_sync', lock_version: 0, tags: [], effective_amount_cents: 10000,
    refund: null, ...o,
  }
}

function group(): InstallmentItem {
  const p1 = tx({ id: 'p1', installment_number: 1, original_description: 'GELADEIRA 01/03' })
  const p2 = tx({ id: 'p2', installment_number: 2, original_description: 'GELADEIRA 02/03', occurred_at: '2026-07-04' })
  return { kind: 'installment', groupId: 'g1', parcels: [p1, p2], total: 20000, representative: p1 }
}

beforeEach(() => {
  globalThis.fetch = vi.fn().mockResolvedValue({
    ok: true, status: 200, json: async () => ({ tags: [] }),
  } as Response) as unknown as typeof fetch
})

function renderSheet(props: Partial<Parameters<typeof InstallmentGroupSheet>[0]> = {}) {
  const handlers = {
    onClose: vi.fn(), onOpenParcel: vi.fn(), onAcceptGroup: vi.fn(), onRejectGroup: vi.fn(),
  }
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <InstallmentGroupSheet item={group()} open mode="inbox" {...handlers} {...props} />
      </MemoryRouter>
    </QueryClientProvider>
  )
  return handlers
}

describe('InstallmentGroupSheet', () => {
  it('lista as parcelas presentes com o descritor original de cada uma', () => {
    renderSheet()
    expect(screen.getByTestId('group-sheet-parcel-p1')).toBeInTheDocument()
    expect(screen.getByTestId('group-sheet-parcel-p2')).toBeInTheDocument()
    expect(screen.getByTestId('parcel-original-p1')).toHaveTextContent('GELADEIRA 01/03')
    expect(screen.getByTestId('parcel-original-p2')).toHaveTextContent('GELADEIRA 02/03')
  })

  it('clicar numa parcela chama onOpenParcel com a transação', async () => {
    const h = renderSheet()
    await userEvent.click(screen.getByTestId('group-sheet-parcel-p2'))
    expect(h.onOpenParcel).toHaveBeenCalledTimes(1)
    expect(h.onOpenParcel.mock.calls[0][0]).toMatchObject({ id: 'p2' })
  })

  it('aceitar todas chama onAcceptGroup e fecha; rejeitar idem', async () => {
    const h = renderSheet()
    await userEvent.click(screen.getByTestId('group-sheet-accept-g1'))
    expect(h.onAcceptGroup).toHaveBeenCalledTimes(1)
    expect(h.onClose).toHaveBeenCalledTimes(1)

    await userEvent.click(screen.getByTestId('group-sheet-reject-g1'))
    expect(h.onRejectGroup).toHaveBeenCalledTimes(1)
    expect(h.onClose).toHaveBeenCalledTimes(2)
  })

  it('modo consolidated esconde o rodapé de ações em massa', () => {
    renderSheet({ mode: 'consolidated' })
    expect(screen.queryByTestId('group-sheet-accept-g1')).not.toBeInTheDocument()
    expect(screen.queryByTestId('group-sheet-reject-g1')).not.toBeInTheDocument()
  })

  it('editar o título e sair do campo persiste o novo título do grupo', async () => {
    renderSheet()
    const input = screen.getByTestId('group-sheet-title-g1')
    await userEvent.clear(input)
    await userEvent.type(input, 'Geladeira Brastemp')
    await userEvent.tab() // blur

    const calls = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls
    const patch = calls.find(([url]) => String(url).includes('/installment_groups/g1'))
    expect(patch).toBeTruthy()
    expect(JSON.parse((patch![1] as RequestInit).body as string)).toMatchObject({
      improved_title: 'Geladeira Brastemp',
    })
  })
})
