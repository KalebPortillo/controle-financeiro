import { useEffect, useState } from 'react'

/**
 * Barra de progresso "simulada" para esperas de IA (análise de tags/categorias).
 * O provedor (Gemini) não expõe progresso real — é uma requisição única — então
 * mostramos etapas que avançam por timer e uma barra que cresce mas satura em
 * ~90%, sinalizando atividade sem prometer um fim falso. Quem chama completa o
 * fluxo de verdade quando o status real muda (a tela desmonta).
 */
export function AnalysisProgress({
  steps,
  intervalMs = 2500,
}: {
  steps: string[]
  intervalMs?: number
}) {
  const [index, setIndex] = useState(0)

  useEffect(() => {
    if (steps.length <= 1) return
    const id = setInterval(() => {
      setIndex((i) => Math.min(i + 1, steps.length - 1))
    }, intervalMs)
    return () => clearInterval(id)
  }, [steps.length, intervalMs])

  // Distribui de ~15% (1ª etapa) até no máx 90% (última), nunca 100%.
  const last = Math.max(steps.length - 1, 1)
  const pct = Math.round(15 + (75 * index) / last)

  return (
    <div className="w-full max-w-xs space-y-2">
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
        <div
          className="h-full rounded-full bg-accent transition-all duration-700 ease-out"
          style={{ width: `${pct}%` }}
          data-testid="analysis-progress-bar"
        />
      </div>
      <p className="text-xs text-muted-foreground" data-testid="analysis-progress-label">
        {steps[index]}
      </p>
    </div>
  )
}
