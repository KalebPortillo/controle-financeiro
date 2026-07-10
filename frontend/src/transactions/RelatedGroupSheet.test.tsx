import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router'
import { RelatedGroupSheet } from './RelatedGroupSheet'
import type { InboxTransaction, RelatedItem } from './useInbox'
import type { InboxItem } from './inboxItems'

type RelatedGroupItem = Extract<InboxItem, { kind: 'related' }>

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 't1', account_id: 'a1', account_name: 'Nubank', account_kind: 'credit_card',
    institution_label: 'Nubank', account_institution_name: 'Nubank', account_brand: null,
    account_last_digits: null, card_last_digits: null, installment_number: null, installment_total: null,
    installment_group_id: null, purchase_date: null, foreign_currency: null, direction: 'debit', amount_cents: 35284, currency: 'BRL',
    occurred_at: '2026-06-04', original_description: 'FIGMA', improved_title: 'Figma',
    ai_confidence: null, ai_suggestion: null, ai_status: 'analyzed', status: 'pending',
    source: 'automatic_sync', lock_version: 0, tags: [], effective_amount_cents: 35284,
    refund: null, related: null, ...o,
  }
}

function rel(o: Partial<RelatedItem> & Pick<RelatedItem, 'role' | 'transaction_id'>): RelatedItem {
  return {
    link_id: `lnk-${o.transaction_id}`, relation_type: 'iof', title: 'X',
    direction: 'debit', amount_cents: 0, occurred_at: '2026-06-05', status: 'pending', ...o,
  }
}

function group(): RelatedGroupItem {
  const anchor = tx({ id: 'p1', related: [rel({ role: 'satellite', transaction_id: 'iof1', amount_cents: 1235 })] })
  const iof = tx({ id: 'iof1', improved_title: null, original_description: 'IOF', amount_cents: 1235, occurred_at: '2026-06-05' })
  return {
    kind: 'related', key: 'p1', anchor, satellites: [iof], members: [anchor, iof],
    memberIds: ['p1', 'iof1'], satelliteTypes: new Map([['iof1', 'iof']]), signedTotalCents: -36519,
  }
}

function renderSheet(props: Partial<Parameters<typeof RelatedGroupSheet>[0]> = {}) {
  const handlers = { onClose: vi.fn(), onOpenMember: vi.fn(), onAcceptGroup: vi.fn(), onRejectGroup: vi.fn() }
  render(
    <MemoryRouter>
      <RelatedGroupSheet item={group()} open {...handlers} {...props} />
    </MemoryRouter>,
  )
  return handlers
}

describe('RelatedGroupSheet', () => {
  it('lista a origem em destaque e o IOF como relacionada', () => {
    renderSheet()
    expect(screen.getByTestId('related-sheet-member-p1')).toHaveTextContent('Origem')
    expect(screen.getByTestId('related-sheet-member-p1')).toHaveTextContent('Figma')
    expect(screen.getByTestId('related-sheet-member-iof1')).toHaveTextContent('IOF')
  })

  // RF10.6/título — a cobrança de IOF (genérica do banco) referencia a compra.
  it('o membro de IOF genérico mostra a referência da compra', () => {
    renderSheet()
    // "IOF" original vira "IOF · Figma" (a loja da compra âncora)
    expect(screen.getByTestId('related-sheet-member-iof1')).toHaveTextContent('IOF · Figma')
  })

  it('mostra o custo combinado e o resumo dos tipos no header', () => {
    renderSheet()
    expect(screen.getByText('Gasto + IOF')).toBeInTheDocument()
  })

  it('clicar num membro chama onOpenMember com a transação', async () => {
    const h = renderSheet()
    await userEvent.click(screen.getByTestId('related-sheet-member-iof1'))
    expect(h.onOpenMember).toHaveBeenCalledTimes(1)
    expect(h.onOpenMember.mock.calls[0][0]).toMatchObject({ id: 'iof1' })
  })

  it('aceitar todas chama onAcceptGroup e fecha; rejeitar idem', async () => {
    const h = renderSheet()
    await userEvent.click(screen.getByTestId('related-sheet-accept-p1'))
    expect(h.onAcceptGroup).toHaveBeenCalledTimes(1)
    expect(h.onClose).toHaveBeenCalledTimes(1)

    await userEvent.click(screen.getByTestId('related-sheet-reject-p1'))
    expect(h.onRejectGroup).toHaveBeenCalledTimes(1)
    expect(h.onClose).toHaveBeenCalledTimes(2)
  })
})
