import { describe, it, expect } from 'vitest'
import { buildInboxItems, type InboxItem } from './inboxItems'
import { splitByPurchaseMonth } from './purchaseSections'
import type { InboxTransaction, RelatedItem } from './useInbox'

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 't1', account_id: 'a1', account_name: 'Nubank', account_kind: 'credit_card',
    institution_label: 'Nubank', account_institution_name: 'Nubank', account_brand: null, account_last_digits: null, card_last_digits: null, installment_number: null, installment_total: null,
    installment_group_id: null, purchase_date: null, foreign_currency: null, direction: 'debit', amount_cents: 10000, currency: 'BRL',
    occurred_at: '2026-10-04', original_description: 'X', improved_title: null,
    ai_confidence: null, ai_suggestion: null, ai_status: 'analyzed', status: 'consolidated',
    source: 'automatic_sync', lock_version: 0, tags: [], effective_amount_cents: 10000,
    refund: null, related: null, ...o,
  }
}

// Parcela N de uma compra feita em `purchase` (purchase_date = âncora retro-calculada).
function parcel(id: string, n: number, total: number, occurred: string, purchase: string): InboxTransaction {
  return tx({ id, installment_number: n, installment_total: total, installment_group_id: `g-${id}`,
    occurred_at: occurred, purchase_date: purchase })
}

const ids = (items: InboxItem[]) =>
  items.map((i) => (i.kind === 'single' ? i.transaction.id : i.kind === 'related' ? `rel:${i.key}` : i.groupId))

const split = (txs: InboxTransaction[], period = '2026-10') =>
  splitByPurchaseMonth(buildInboxItems(txs, { groupInstallments: false }), period)

describe('splitByPurchaseMonth', () => {
  it('compras do mês em cima; parcelas de compras anteriores embaixo', () => {
    const { current, previous } = split([
      parcel('magalu-4', 4, 6, '2026-10-30', '2026-07-30'),
      tx({ id: 'mercado', occurred_at: '2026-10-08' }),
      parcel('amazon-1', 1, 5, '2026-10-07', '2026-10-07'),
    ])
    expect(ids(current)).toEqual(['mercado', 'amazon-1'])
    expect(ids(previous)).toEqual(['magalu-4'])
  })

  it('compras do mês ordenadas pela data da compra, mais recente primeiro', () => {
    const { current } = split([
      tx({ id: 'a', occurred_at: '2026-10-02' }),
      tx({ id: 'b', occurred_at: '2026-10-20' }),
      tx({ id: 'c', occurred_at: '2026-10-11' }),
    ])
    expect(ids(current)).toEqual(['b', 'c', 'a'])
  })

  it('parcelas anteriores ordenadas pela data da parcela, mais recente primeiro', () => {
    const { previous } = split([
      parcel('p15', 8, 12, '2026-10-15', '2026-03-15'),
      parcel('p30', 4, 6, '2026-10-30', '2026-07-30'),
      parcel('p22', 2, 3, '2026-10-22', '2026-09-22'),
    ])
    expect(ids(previous)).toEqual(['p30', 'p22', 'p15'])
  })

  it('gasto avulso fica nas compras do mês mesmo com purchaseDate do mês anterior no cartão', () => {
    // compra 30/09 que só postou em 01/10: não é parcela, segue a data do extrato.
    const { current, previous } = split([tx({ id: 'virada', occurred_at: '2026-10-01', purchase_date: '2026-09-30' })])
    expect(ids(current)).toEqual(['virada'])
    expect(previous).toEqual([])
  })

  it('parcela sem purchase_date cai na data da própria parcela', () => {
    const { current } = split([tx({ id: 'p', installment_number: 2, installment_total: 3, occurred_at: '2026-10-05' })])
    expect(ids(current)).toEqual(['p'])
  })

  it('grupo de relacionadas (compra + IOF) segue a âncora', () => {
    const r = (o: Partial<RelatedItem> & Pick<RelatedItem, 'role' | 'transaction_id'>): RelatedItem => ({
      link_id: `l-${o.transaction_id}`, relation_type: 'iof', title: 'x', direction: 'debit',
      amount_cents: 0, occurred_at: '2026-10-05', status: 'consolidated', ...o,
    })
    const buy = tx({ id: 'buy', occurred_at: '2026-10-05', related: [r({ role: 'satellite', transaction_id: 'iof' })] })
    const iof = tx({ id: 'iof', occurred_at: '2026-10-06', related: [r({ role: 'origin', transaction_id: 'buy' })] })
    const { current, previous } = split([buy, iof])
    expect(ids(current)).toEqual(['rel:buy'])
    expect(previous).toEqual([])
  })
})
