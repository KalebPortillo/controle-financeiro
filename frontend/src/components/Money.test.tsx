import { describe, it, expect } from 'vitest'
import { render } from '@testing-library/react'
import { Money } from './Money'

function moneyEl(container: HTMLElement) {
  return container.querySelector('.cf-money') as HTMLElement
}

// toLocaleString usa espaço não-quebrável (U+00A0) entre R$ e o número;
// \s casa o nbsp, então colapsamos qualquer espaço em um espaço comum.
function text(el: HTMLElement) {
  return (el.textContent ?? '').replace(/\s+/g, ' ').trim()
}

describe('<Money />', () => {
  it('formata em R$ pt-BR com − (em-dash) para negativos', () => {
    const { container } = render(<Money cents={-123456} />)
    expect(text(moneyEl(container))).toBe('− R$ 1.234,56')
  })

  it('receita (positivo + signed) ganha verde via .cf-money--positive', () => {
    const { container } = render(<Money cents={6500_00} signed />)
    const el = moneyEl(container)
    expect(el.classList).toContain('cf-money--positive')
    expect(text(el)).toBe('+ R$ 6.500,00')
  })

  it('gasto (negativo) fica neutro — sem classe de cor', () => {
    const { container } = render(<Money cents={-50_00} signed />)
    const el = moneyEl(container)
    expect(el.classList).not.toContain('cf-money--positive')
    expect(el.classList).not.toContain('cf-money--negative')
  })

  it('sem signed, positivo não recebe verde (não é necessariamente receita)', () => {
    const { container } = render(<Money cents={50_00} />)
    expect(moneyEl(container).classList).not.toContain('cf-money--positive')
  })
})
