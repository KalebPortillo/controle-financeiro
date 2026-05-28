import { useRef, useState, type ReactNode, type PointerEvent } from 'react'
import { Check, X } from 'lucide-react'

// Deslize além deste ponto (px) arma a ação ao soltar.
const THRESHOLD = 90

/**
 * Linha com swipe-to-action (padrão mobile). Arrastar revela um fundo colorido:
 * esquerda → aceitar (verde), direita → rejeitar (vermelho). Passando o limiar,
 * o fundo intensifica indicando que soltar efetua a ação. Um toque sem arrasto
 * dispara onClick (abrir detalhe). Funciona com mouse e touch (pointer events).
 */
export function SwipeableRow({
  onConfirm,
  onReject,
  onClick,
  children,
  testid,
}: {
  onConfirm: () => void
  onReject: () => void
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
    // Resistência leve nas pontas, limita o curso.
    setDx(Math.max(-160, Math.min(160, d)))
  }

  const finish = () => {
    if (startX.current === null) return
    const d = dx
    startX.current = null
    setDragging(false)
    if (d <= -THRESHOLD) onConfirm()
    else if (d >= THRESHOLD) onReject()
    setDx(0)
  }

  const onPointerUp = () => {
    const wasDrag = moved.current
    finish()
    if (!wasDrag) onClick()
  }

  const armedConfirm = dx <= -THRESHOLD // esquerda
  const armedReject = dx >= THRESHOLD // direita

  return (
    <div
      className="relative overflow-hidden border-b border-border last:border-b-0"
      data-testid={testid}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={finish}
    >
      {/* fundo rejeitar — revelado ao arrastar pra direita (lado esquerdo) */}
      <div
        className={`absolute inset-y-0 left-0 flex items-center gap-2 pl-4 text-sm font-medium transition-colors ${
          armedReject ? 'bg-destructive text-destructive-foreground' : 'bg-destructive/30 text-destructive'
        }`}
        style={{ width: Math.max(0, dx) }}
        aria-hidden
      >
        {dx > 24 && (
          <>
            <X size={16} />
            {armedReject && <span>Rejeitar</span>}
          </>
        )}
      </div>

      {/* fundo aceitar — revelado ao arrastar pra esquerda (lado direito) */}
      <div
        className={`absolute inset-y-0 right-0 flex items-center justify-end gap-2 pr-4 text-sm font-medium transition-colors ${
          armedConfirm ? 'bg-[var(--success-vivid)] text-white' : 'bg-success/30 text-success'
        }`}
        style={{ width: Math.max(0, -dx) }}
        aria-hidden
      >
        {dx < -24 && (
          <>
            {armedConfirm && <span>Aceitar</span>}
            <Check size={16} />
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
