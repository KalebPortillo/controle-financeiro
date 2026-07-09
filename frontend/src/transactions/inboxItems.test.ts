import { describe, it, expect } from 'vitest'
import { buildInboxItems, type InboxItem } from './inboxItems'
import type { InboxTransaction, RelatedItem } from './useInbox'

// Rótulo curto de um item pra asserções de ordem/posição.
function label(i: InboxItem): string {
  if (i.kind === 'single') return i.transaction.id
  if (i.kind === 'installment') return `grp:${i.groupId}`
  return `rel:${i.key}`
}

function tx(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 't1', account_id: 'a1', account_name: 'Nubank', account_kind: 'credit_card',
    institution_label: 'Nubank', account_institution_name: 'Nubank', account_brand: null, account_last_digits: null, card_last_digits: null, installment_number: null, installment_total: null,
    installment_group_id: null, purchase_date: null, foreign_currency: null, direction: 'debit', amount_cents: 10000, currency: 'BRL',
    occurred_at: '2026-06-04', original_description: 'X', improved_title: null,
    ai_confidence: null, ai_suggestion: null, ai_status: 'analyzed', status: 'pending',
    source: 'automatic_sync', lock_version: 0, tags: [], effective_amount_cents: 10000,
    refund: null, related: null, ...o,
  }
}

// Constrói o item de vínculo (satélite ou origem) que a API embute em `related`.
function rel(o: Partial<RelatedItem> & Pick<RelatedItem, 'role' | 'transaction_id'>): RelatedItem {
  return {
    link_id: `lnk-${o.transaction_id}`, relation_type: 'iof', title: 'X',
    direction: 'debit', amount_cents: 0, occurred_at: '2026-06-04', status: 'pending', ...o,
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
    expect(items.map(label))
      .toEqual(['a', 'grp:g1', 'b'])
  })

  it('grupos diferentes viram itens diferentes', () => {
    const items = buildInboxItems([
      tx({ id: 'p1', installment_number: 1, installment_total: 3, installment_group_id: 'g1' }),
      tx({ id: 'q1', installment_number: 1, installment_total: 6, installment_group_id: 'g2' }),
    ])
    expect(items).toHaveLength(2)
  })

  it('purchaseDate do grupo = purchase_date das parcelas', () => {
    const items = buildInboxItems([
      tx({ id: 'p1', installment_number: 1, installment_total: 3, installment_group_id: 'g1',
        occurred_at: '2026-06-10', purchase_date: '2026-05-14' }),
      tx({ id: 'p2', installment_number: 2, installment_total: 3, installment_group_id: 'g1',
        occurred_at: '2026-07-10', purchase_date: '2026-05-14' }),
    ])
    const item = items[0]
    if (item.kind !== 'installment') throw new Error('esperava installment')
    expect(item.purchaseDate).toBe('2026-05-14') // não a data da parcela
  })

  it('purchaseDate cai na 1ª parcela quando não há purchase_date', () => {
    const items = buildInboxItems([
      tx({ id: 'p2', installment_number: 2, installment_total: 3, installment_group_id: 'g1',
        occurred_at: '2026-07-10', purchase_date: null }),
      tx({ id: 'p1', installment_number: 1, installment_total: 3, installment_group_id: 'g1',
        occurred_at: '2026-06-10', purchase_date: null }),
    ])
    const item = items[0]
    if (item.kind !== 'installment') throw new Error('esperava installment')
    expect(item.purchaseDate).toBe('2026-06-10') // a parcela mais antiga
  })

  it('ordena a lista por data desc (compra do parcelamento, não a parcela)', () => {
    const items = buildInboxItems([
      tx({ id: 'a', occurred_at: '2026-06-20' }),
      // parcela recente (07/10) mas compra antiga (05/14) → grupo entra por 05/14
      tx({ id: 'p1', installment_number: 1, installment_total: 3, installment_group_id: 'g1',
        occurred_at: '2026-07-10', purchase_date: '2026-05-14' }),
      tx({ id: 'b', occurred_at: '2026-06-01' }),
    ])
    expect(items.map(label))
      .toEqual(['a', 'b', 'grp:g1']) // 06/20, 06/01, 05/14
  })
})

describe('buildInboxItems — relacionadas (RF23 Fase 2)', () => {
  // Compra estrangeira (âncora) + IOF satélite, ambos presentes na lista.
  const purchase = () =>
    tx({ id: 'p1', improved_title: 'Figma', amount_cents: 35284, occurred_at: '2026-06-04',
      related: [rel({ role: 'satellite', transaction_id: 'iof1', amount_cents: 1235 })] })
  const iof = () =>
    tx({ id: 'iof1', original_description: 'IOF', amount_cents: 1235, occurred_at: '2026-06-05',
      related: [rel({ role: 'origin', transaction_id: 'p1', amount_cents: 35284 })] })

  it('âncora + satélites presentes agregam num item related', () => {
    const items = buildInboxItems([purchase(), iof()])
    expect(items).toHaveLength(1)
    const item = items[0]
    expect(item.kind).toBe('related')
    if (item.kind !== 'related') return
    expect(item.anchor.id).toBe('p1')
    expect(item.satellites.map((s) => s.id)).toEqual(['iof1'])
    expect(item.memberIds).toEqual(['p1', 'iof1'])
    // total combinado assinado: compra + IOF (ambos débito) = −(35284 + 1235)
    expect(item.signedTotalCents).toBe(-36519)
  })

  it('o item related ocupa a posição da âncora e consome o satélite', () => {
    const items = buildInboxItems([
      tx({ id: 'a', occurred_at: '2026-06-10' }),
      iof(),        // satélite aparece antes da âncora na lista
      purchase(),
      tx({ id: 'b', occurred_at: '2026-06-01' }),
    ])
    // ordena por data desc; grupo entra pela data da âncora (06/04)
    expect(items.map(label))
      .toEqual(['a', 'rel:p1', 'b'])
  })

  it('satélite ausente → âncora fica avulsa (não agrupa)', () => {
    const items = buildInboxItems([purchase()]) // iof1 não está na lista
    expect(items).toHaveLength(1)
    expect(items[0].kind).toBe('single')
  })

  it('âncora ausente → satélite fica avulso (não agrupa)', () => {
    const items = buildInboxItems([iof()]) // p1 não está na lista
    expect(items).toHaveLength(1)
    expect(items[0].kind).toBe('single')
  })

  it('parcelamento tem prioridade: âncora parcelada não vira grupo related', () => {
    const parceledAnchor = tx({ id: 'p1', installment_number: 1, installment_total: 3,
      installment_group_id: 'g1', related: [rel({ role: 'satellite', transaction_id: 'iof1' })] })
    const items = buildInboxItems([parceledAnchor, iof()])
    expect(items.map((i) => i.kind).sort()).toEqual(['installment', 'single'])
  })
})

describe('buildInboxItems — estornos aninhados (RF10.6)', () => {
  // Compra (débito) + estornos (créditos) que a apontam via related 'refund'.
  const buy = (refundIds: string[]) =>
    tx({ id: 'buy', improved_title: 'Amazon', direction: 'debit', amount_cents: 103000,
      effective_amount_cents: 103000, occurred_at: '2026-06-28',
      related: refundIds.map((id) =>
        rel({ role: 'satellite', relation_type: 'refund', link_kind: 'refund', transaction_id: id, direction: 'credit' })) })
  const refund = (id: string, cents: number) =>
    tx({ id, direction: 'credit', amount_cents: cents, occurred_at: '2026-06-28',
      original_description: 'Crédito de AMAZON',
      related: [rel({ role: 'origin', relation_type: 'refund', link_kind: 'refund', transaction_id: 'buy', direction: 'debit' })] })

  it('a compra e seus estornos presentes viram um item related (bruto − estornos)', () => {
    const items = buildInboxItems([buy(['r1', 'r2']), refund('r1', 5918), refund('r2', 7107)])
    expect(items).toHaveLength(1)
    const item = items[0]
    expect(item.kind).toBe('related')
    if (item.kind !== 'related') return
    expect(item.anchor.id).toBe('buy')
    expect(item.satellites.map((s) => s.id).sort()).toEqual(['r1', 'r2'])
    // signed: −103000 (débito) + 5918 + 7107 (créditos) = −90 (mil e pouco)
    expect(item.signedTotalCents).toBe(-103000 + 5918 + 7107)
  })

  it('estorno parcial: agrupa os estornos PRESENTES sem exigir todos', () => {
    // a compra referencia r1 e r2, mas só r1 está na lista
    const items = buildInboxItems([buy(['r1', 'r2']), refund('r1', 5918)])
    expect(items).toHaveLength(1)
    const item = items[0]
    expect(item.kind).toBe('related')
    if (item.kind !== 'related') return
    expect(item.satellites.map((s) => s.id)).toEqual(['r1'])
  })

  it('estorno consumido não renderiza avulso', () => {
    const items = buildInboxItems([buy(['r1']), refund('r1', 5918)])
    const singles = items.filter((i) => i.kind === 'single')
    expect(singles).toHaveLength(0)
  })
})
