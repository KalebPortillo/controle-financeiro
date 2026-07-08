import { describe, it, expect } from 'vitest'
import { formatDayMonth, signedCents, displayTitle } from './display'

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
})
