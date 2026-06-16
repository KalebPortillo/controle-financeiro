import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { SwipeableRow } from './SwipeableRow'

function setup() {
  const onClick = vi.fn()
  const left = vi.fn()
  const right = vi.fn()
  render(
    <SwipeableRow
      testid="row"
      onClick={onClick}
      swipeLeft={{ onAction: left, label: 'Rejeitar', icon: null, idleClass: '', armedClass: '' }}
      swipeRight={{ onAction: right, label: 'Consolidar', icon: null, idleClass: '', armedClass: '' }}
    >
      <span>conteúdo</span>
    </SwipeableRow>
  )
  return { row: screen.getByTestId('row'), onClick, left, right }
}

// THRESHOLD interno é 90px.
const swipe = (row: HTMLElement, from: number, to: number) => {
  fireEvent.pointerDown(row, { clientX: from, pointerId: 1 })
  fireEvent.pointerMove(row, { clientX: to, pointerId: 1 })
  fireEvent.pointerUp(row, { clientX: to, pointerId: 1 })
}

describe('SwipeableRow', () => {
  it('um toque sem arrasto dispara onClick e nenhuma ação de swipe', () => {
    const { row, onClick, left, right } = setup()
    fireEvent.pointerDown(row, { clientX: 100, pointerId: 1 })
    fireEvent.pointerUp(row, { clientX: 100, pointerId: 1 })
    expect(onClick).toHaveBeenCalledTimes(1)
    expect(left).not.toHaveBeenCalled()
    expect(right).not.toHaveBeenCalled()
  })

  it('arrastar pra esquerda além do limiar dispara swipeLeft, não onClick', () => {
    const { row, onClick, left, right } = setup()
    swipe(row, 200, 100) // dx = -100 (< -90)
    expect(left).toHaveBeenCalledTimes(1)
    expect(right).not.toHaveBeenCalled()
    expect(onClick).not.toHaveBeenCalled()
  })

  it('arrastar pra direita além do limiar dispara swipeRight, não onClick', () => {
    const { row, onClick, left, right } = setup()
    swipe(row, 100, 200) // dx = +100 (> 90)
    expect(right).toHaveBeenCalledTimes(1)
    expect(left).not.toHaveBeenCalled()
    expect(onClick).not.toHaveBeenCalled()
  })

  it('arrasto abaixo do limiar não dispara ação nem onClick (foi arrasto, não toque)', () => {
    const { row, onClick, left, right } = setup()
    swipe(row, 100, 150) // dx = +50 (< 90)
    expect(left).not.toHaveBeenCalled()
    expect(right).not.toHaveBeenCalled()
    expect(onClick).not.toHaveBeenCalled()
  })
})
