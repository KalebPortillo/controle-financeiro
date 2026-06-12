import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { AccountTag } from './AccountTag'

describe('<AccountTag />', () => {
  it('mostra instituição + "cartão" para credit_card', () => {
    render(<AccountTag kind="credit_card" institutionLabel="Nubank" accountName="Nubank CC" />)
    expect(screen.getByTestId('account-tag')).toHaveTextContent('Nubank · cartão')
  })

  it('mostra instituição + "conta" para checking', () => {
    render(<AccountTag kind="checking" institutionLabel="Inter" accountName="Inter CC" />)
    expect(screen.getByTestId('account-tag')).toHaveTextContent('Inter · conta')
  })

  it('cai para o account_name quando não há instituição', () => {
    render(<AccountTag kind="checking" institutionLabel={null} accountName="Dinheiro / Externo" />)
    expect(screen.getByTestId('account-tag')).toHaveTextContent('Dinheiro / Externo · conta')
  })

  it('sem kind mostra só a fonte', () => {
    render(<AccountTag kind={null} institutionLabel="Nubank" accountName={null} />)
    expect(screen.getByTestId('account-tag')).toHaveTextContent('Nubank')
  })
})
