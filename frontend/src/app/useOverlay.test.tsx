import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, useLocation } from 'react-router'
import { useOverlay } from './useOverlay'

function Harness() {
  const { get, push, close, replaceWith } = useOverlay()
  const loc = useLocation()
  return (
    <div>
      <span data-testid="search">{loc.search}</span>
      <span data-testid="tx">{get('tx') ?? ''}</span>
      <button onClick={() => push((p) => p.set('tx', 'abc'))}>open-tx</button>
      <button onClick={() => push((p) => { p.delete('group'); p.set('tx', 'abc') })}>open-parcel</button>
      <button onClick={() => close('tx')}>close-tx</button>
      <button onClick={() => replaceWith('/contas')}>go-contas</button>
    </div>
  )
}

function renderAt(entries: string[], index?: number) {
  return render(
    <MemoryRouter initialEntries={entries} initialIndex={index}>
      <Harness />
    </MemoryRouter>,
  )
}

describe('useOverlay', () => {
  it('push adiciona o param na URL (abre o overlay)', async () => {
    renderAt(['/inbox'])
    await userEvent.click(screen.getByText('open-tx'))
    expect(screen.getByTestId('search').textContent).toBe('?tx=abc')
    expect(screen.getByTestId('tx').textContent).toBe('abc')
  })

  it('close volta no histórico quando o overlay foi aberto via push (back fecha)', async () => {
    renderAt(['/inbox'])
    await userEvent.click(screen.getByText('open-tx'))
    expect(screen.getByTestId('search').textContent).toBe('?tx=abc')
    await userEvent.click(screen.getByText('close-tx'))
    // navigate(-1) restaura a entrada anterior, sem o param.
    expect(screen.getByTestId('search').textContent).toBe('')
  })

  it('close em deep-link (sem histórico interno) remove o param via replace', async () => {
    // Entrada inicial já com ?tx — location.key === "default", não há back interno.
    renderAt(['/inbox?tx=abc'])
    expect(screen.getByTestId('tx').textContent).toBe('abc')
    await userEvent.click(screen.getByText('close-tx'))
    expect(screen.getByTestId('search').textContent).toBe('')
  })

  it('abrir parcela mantém o back pro grupo e troca o overlay visível', async () => {
    renderAt(['/inbox?group=g1'])
    await userEvent.click(screen.getByText('open-parcel'))
    // group sai da URL visível, tx entra; mas é um push → back restaura o grupo.
    expect(screen.getByTestId('search').textContent).toBe('?tx=abc')
    await userEvent.click(screen.getByText('close-tx'))
    expect(screen.getByTestId('search').textContent).toBe('?group=g1')
  })
})
