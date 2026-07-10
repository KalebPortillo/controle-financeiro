import { describe, it, expect } from 'vitest'
import { formatDayMonth, signedCents, displayTitle, groupAnchorTitle } from './display'
import type { InboxTransaction } from './useInbox'

describe('display helpers', () => {
  it('formatDayMonth → dd/mm', () => {
    expect(formatDayMonth('2026-05-19')).toBe('19/05')
  })

  it('signedCents negates debits, keeps credits positive', () => {
    expect(signedCents({ direction: 'debit', amount_cents: 500 })).toBe(-500)
    expect(signedCents({ direction: 'credit', amount_cents: 500 })).toBe(500)
  })

  it('displayTitle prefers improved_title, falls back to original', () => {
    expect(displayTitle({ improved_title: 'Amazon', original_description: 'AMZN' })).toBe('Amazon')
    expect(displayTitle({ improved_title: null, original_description: 'AMZN' })).toBe('AMZN')
  })

  it('groupAnchorTitle usa a compra vinculada quando a âncora é a cobrança de IOF', () => {
    const iofCharge = {
      improved_title: 'IOF Compra Internacional', original_description: 'IOF de compra internacional',
      related: [{ role: 'origin', relation_type: 'iof', title: 'Amazon PZ7SW7MV3', transaction_id: 'buy' }],
    } as unknown as InboxTransaction
    expect(groupAnchorTitle(iofCharge)).toBe('IOF · Amazon PZ7SW7MV3')

    const purchase = { improved_title: 'Amazon', original_description: 'AMZN', related: null } as unknown as InboxTransaction
    expect(groupAnchorTitle(purchase)).toBe('Amazon')
  })
})
