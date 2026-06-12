import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { AccountTag } from './AccountTag'
import type { InboxTransaction } from './useInbox'

function src(o: Partial<InboxTransaction> = {}): InboxTransaction {
  return {
    id: 't1', account_id: 'a1', account_name: 'Nubank CC', account_kind: 'credit_card',
    institution_label: 'Nubank', account_institution_name: 'Nubank', account_brand: null,
    account_last_digits: null, card_last_digits: null, installment_number: null, installment_total: null,
    installment_group_id: null, direction: 'debit', amount_cents: 1, currency: 'BRL',
    occurred_at: '2026-06-01', original_description: 'X', improved_title: null,
    ai_confidence: null, ai_suggestion: null, ai_status: 'analyzed', status: 'pending',
    source: 'automatic_sync', lock_version: 0, tags: [], effective_amount_cents: 1, refund: null, ...o,
  }
}

describe('<AccountTag />', () => {
  it('cartão: banco · bandeira dígitos', () => {
    render(<AccountTag t={src({ account_kind: 'credit_card', account_institution_name: 'Nubank', account_brand: 'Mastercard', account_last_digits: '9437' })} />)
    expect(screen.getByTestId('account-tag')).toHaveTextContent('Nubank · Mastercard 9437')
  })

  it('cartão sem bandeira: banco · cartão dígitos', () => {
    render(<AccountTag t={src({ account_kind: 'credit_card', account_institution_name: 'Inter', account_brand: null, account_last_digits: '1234' })} />)
    expect(screen.getByTestId('account-tag')).toHaveTextContent('Inter · cartão 1234')
  })

  it('prefere o dígito do cartão da compra (card_last_digits) ao da conta', () => {
    render(<AccountTag t={src({ account_kind: 'credit_card', account_institution_name: 'Nubank', account_brand: 'Mastercard', account_last_digits: '0000', card_last_digits: '5190' })} />)
    expect(screen.getByTestId('account-tag')).toHaveTextContent('Nubank · Mastercard 5190')
  })

  it('conta: banco · conta corrente', () => {
    render(<AccountTag t={src({ account_kind: 'checking', account_institution_name: 'Inter' })} />)
    expect(screen.getByTestId('account-tag')).toHaveTextContent('Inter · conta corrente')
  })

  it('cai para institution_label quando não há nome do conector', () => {
    render(<AccountTag t={src({ account_kind: 'checking', account_institution_name: null, institution_label: 'Manual' })} />)
    expect(screen.getByTestId('account-tag')).toHaveTextContent('Manual · conta corrente')
  })
})
