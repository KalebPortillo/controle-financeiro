import { describe, it, expect } from 'vitest'
import { normalizeForSearch, transactionMatchesQuery } from './searchMatch'
import type { InboxTransaction } from './useInbox'

function t(o: Partial<InboxTransaction>): InboxTransaction {
  return { improved_title: null, original_description: '', tags: [], ...o } as InboxTransaction
}

describe('normalizeForSearch', () => {
  it('strips accents and lowercases', () => {
    expect(normalizeForSearch('Açaí da Praia')).toBe('acai da praia')
    expect(normalizeForSearch('CAFÉ')).toBe('cafe')
  })
})

describe('transactionMatchesQuery', () => {
  it('empty query matches everything', () => {
    expect(transactionMatchesQuery(t({ original_description: 'X' }), '  ')).toBe(true)
  })

  it('matches improved_title accent- and case-insensitively', () => {
    const tx = t({ improved_title: 'Açaí da Praia' })
    expect(transactionMatchesQuery(tx, 'acai')).toBe(true)
    expect(transactionMatchesQuery(tx, 'PRAIA')).toBe(true)
  })

  it('matches the original bank description by substring', () => {
    expect(transactionMatchesQuery(t({ original_description: 'AMZN MKTP US' }), 'mktp')).toBe(true)
  })

  it('matches a tag name', () => {
    const tx = t({ tags: [{ id: '1', name: 'Alimentação', color: null, icon: null }] })
    expect(transactionMatchesQuery(tx, 'aliment')).toBe(true)
  })

  it('does not match unrelated text', () => {
    expect(transactionMatchesQuery(t({ improved_title: 'Spotify' }), 'amazon')).toBe(false)
  })
})
