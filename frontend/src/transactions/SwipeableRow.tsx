import { useRef, useState, type ReactNode, type PointerEvent } from 'react'

// Deslize além deste ponto (px) arma a ação ao soltar.
const THRESHOLD = 90

export type SwipeAction = {
  onAction: () => void
  label: string
  icon: ReactNode
  idleClass: string // cor antes do limiar
  armedClass: string // cor passando o limiar (vai efetuar ao soltar)
}

/**
 * Linha com swipe-to-action (padrão mobile). Arrastar revela um fundo colorido:
 * pra esquerda dispara `swipeLeft`, pra direita `swipeRight`. Passando o limiar,
 * o fundo intensifica indicando que soltar efetua a ação. Um toque sem arrasto
 * dispara onClick. Funciona com mouse e touch (pointer events).
 */
export function SwipeableRow({
  swipeLeft,
  swipeRight,
  onClick,
  children,
  testid,
}: {
  swipeLeft: SwipeAction
  swipeRight: SwipeAction
  onClick: () => void
  children: ReactNode
  testid?: string
}) {
  const [dx, setDx] = useState(0)
  const [dragging, setDragging] = useState(false)
  const startX = useRef<number | null>(null)
  const moved = useRef(false)

  const onPointerDown = (e: PointerEvent) => {
    startX.current = e.clientX
    moved.current = false
    setDragging(true)
    try {
      ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
    } catch {
      // happy-dom / browsers sem pointer capture — segue sem capturar.
    }
  }

  const onPointerMove = (e: PointerEvent) => {
    if (startX.current === null) return
    const d = e.clientX - startX.current
    if (Math.abs(d) > 4) moved.current = true
    setDx(Math.max(-160, Math.min(160, d)))
  }

  const finish = () => {
    if (startX.current === null) return
    const d = dx
    startX.current = null
    setDragging(false)
    if (d <= -THRESHOLD) swipeLeft.onAction()
    else if (d >= THRESHOLD) swipeRight.onAction()
    setDx(0)
  }

  const onPointerUp = () => {
    const wasDrag = moved.current
    finish()
    if (!wasDrag) onClick()
  }

  const armedLeft = dx <= -THRESHOLD // arrastando pra esquerda
  const armedRight = dx >= THRESHOLD // arrastando pra direita

  return (
    <div
      className="relative overflow-hidden border-b border-border last:border-b-0"
      data-testid={testid}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={finish}
    >
      {/* fundo do swipe-right — revelado ao arrastar pra direita (lado esquerdo) */}
      <div
        className={`absolute inset-y-0 left-0 flex items-center gap-2 pl-4 text-sm font-medium transition-colors ${
          armedRight ? swipeRight.armedClass : swipeRight.idleClass
        }`}
        style={{ width: Math.max(0, dx) }}
        aria-hidden
      >
        {dx > 24 && (
          <>
            {swipeRight.icon}
            {armedRight && <span>{swipeRight.label}</span>}
          </>
        )}
      </div>

      {/* fundo do swipe-left — revelado ao arrastar pra esquerda (lado direito) */}
      <div
        className={`absolute inset-y-0 right-0 flex items-center justify-end gap-2 pr-4 text-sm font-medium transition-colors ${
          armedLeft ? swipeLeft.armedClass : swipeLeft.idleClass
        }`}
        style={{ width: Math.max(0, -dx) }}
        aria-hidden
      >
        {dx < -24 && (
          <>
            {armedLeft && <span>{swipeLeft.label}</span>}
            {swipeLeft.icon}
          </>
        )}
      </div>

      {/* conteúdo arrastável */}
      <div
        className="relative bg-background touch-pan-y"
        style={{
          transform: `translateX(${dx}px)`,
          transition: dragging ? 'none' : 'transform 160ms ease',
        }}
      >
        {children}
      </div>
    </div>
  )
}
