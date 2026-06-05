import { useEffect, useState } from 'react'

/**
 * Barra de progresso para esperas de IA (análise de tags/categorias).
 *
 * Dois modos:
 * - REAL (`pct` numérico, 0..1): mostra o progresso medido — quantas transações
 *   já foram analisadas (anda em degraus de batch). A barra pode chegar a 100%.
 * - SIMULADO (`pct` ausente): o provedor não expõe progresso por requisição
 *   única, então etapas avançam por timer e a barra cresce mas satura em ~90%,
 *   sinalizando atividade sem prometer um fim falso. Quem chama completa o fluxo
 *   de verdade quando o status real muda (a tela desmonta).
 */
export function AnalysisProgress({
  steps,
  intervalMs = 2500,
  pct,
}: {
  steps: string[]
  intervalMs?: number
  pct?: number | null
}) {
  const [index, setIndex] = useState(0)
  const real = typeof pct === 'number'

  useEffect(() => {
    if (real || steps.length <= 1) return
    const id = setInterval(() => {
      setIndex((i) => Math.min(i + 1, steps.length - 1))
    }, intervalMs)
    return () => clearInterval(id)
  }, [real, steps.length, intervalMs])

  // Real: pct medido (0..100). Simulado: ~15% (1ª etapa) até no máx 90%.
  const last = Math.max(steps.length - 1, 1)
  const width = real
    ? Math.round(Math.min(Math.max(pct as number, 0), 1) * 100)
    : Math.round(15 + (75 * index) / last)

  const label = real
    ? steps[Math.min(Math.round((width / 100) * last), last)]
    : steps[index]

  return (
    <div className="w-full max-w-xs space-y-2">
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
        <div
          className="h-full rounded-full bg-accent transition-all duration-700 ease-out"
          style={{ width: `${width}%` }}
          data-testid="analysis-progress-bar"
        />
      </div>
      <p className="text-xs text-muted-foreground" data-testid="analysis-progress-label">
        {label}
      </p>
    </div>
  )
}
