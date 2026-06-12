import { describe, it, expect } from 'vitest'
import { buildInboxItems } from './inboxItems'
import type { InboxTransaction } from './useInbox'

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 't1', account_id: 'a1', account_name: 'Nubank', account_kind: 'credit_card',
    institution_label: 'Nubank', account_institution_name: 'Nubank', account_brand: null, account_last_digits: null, installment_number: null, installment_total: null,
    installment_group_id: null, direction: 'debit', amount_cents: 10000, currency: 'BRL',
    occurred_at: '2026-06-04', original_description: 'X', improved_title: null,
    ai_confidence: null, ai_suggestion: null, ai_status: 'analyzed', status: 'pending',
    source: 'automatic_sync', lock_version: 0, tags: [], effective_amount_cents: 10000,
    refund: null, ...o,
  }
}

describe('buildInboxItems', () => {
  it('gasto avulso vira item single', () => {
    const items = buildInboxItems([tx({ id: 'a' })])
    expect(items).toHaveLength(1)
    expect(items[0]).toMatchObject({ kind: 'single' })
  })

  it('parcelas do mesmo grupo agregam num item com total somado', () => {
    const items = buildInboxItems([
      tx({ id: 'p1', installment_number: 1, installment_total: 12, installment_group_id: 'g1', amount_cents: 10000 }),
      tx({ id: 'p2', installment_number: 2, installment_total: 12, installment_group_id: 'g1', amount_cents: 10000 }),
    ])
    expect(items).toHaveLength(1)
    const item = items[0]
    expect(item.kind).toBe('installment')
    if (item.kind !== 'installment') return
    expect(item.parcels).toHaveLength(2)
    expect(item.total).toBe(20000)
  })

  it('ordena parcelas por número e o representante tem título', () => {
    const items = buildInboxItems([
      tx({ id: 'p2', installment_number: 2, installment_total: 12, installment_group_id: 'g1', improved_title: 'Geladeira' }),
      tx({ id: 'p1', installment_number: 1, installment_total: 12, installment_group_id: 'g1', improved_title: null }),
    ])
    const item = items[0]
    if (item.kind !== 'installment') throw new Error('esperava installment')
    expect(item.parcels.map((p) => p.id)).toEqual(['p1', 'p2'])
    expect(item.representative.id).toBe('p2') // a que tem título
  })

  it('o grupo ocupa a posição da 1ª parcela; avulsos preservam ordem', () => {
    const items = buildInboxItems([
      tx({ id: 'a' }),
      tx({ id: 'p1', installment_number: 1, installment_total: 3, installment_group_id: 'g1' }),
      tx({ id: 'b' }),
      tx({ id: 'p2', installment_number: 2, installment_total: 3, installment_group_id: 'g1' }),
    ])
    expect(items.map((i) => (i.kind === 'single' ? i.transaction.id : `grp:${i.groupId}`)))
      .toEqual(['a', 'grp:g1', 'b'])
  })

  it('grupos diferentes viram itens diferentes', () => {
    const items = buildInboxItems([
      tx({ id: 'p1', installment_number: 1, installment_total: 3, installment_group_id: 'g1' }),
      tx({ id: 'q1', installment_number: 1, installment_total: 6, installment_group_id: 'g2' }),
    ])
    expect(items).toHaveLength(2)
  })
})
