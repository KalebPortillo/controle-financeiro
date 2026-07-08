import type { BudgetStatus } from './useBudgets'

// Cor da barra por status (RF8.5): verde até <80%, âmbar 80–99%, vermelho ≥100%.
// Usa os tokens *-vivid (comentados no design como cores de orçamento).
const FILL: Record<BudgetStatus, string> = {
  ok:       'var(--success-vivid)',
  warning:  'var(--warning-vivid)',
  exceeded: 'var(--destructive-vivid)',
}

/**
 * Barra de progresso horizontal de um orçamento (RF8.4). Preenchimento limitado a
 * 100% da largura mesmo quando estourado (a cor vermelha comunica o excesso).
 */
export function BudgetProgressBar({ pct, status }: { pct: number; status: BudgetStatus }) {
  return (
    <div
      className="h-2 w-full overflow-hidden rounded-full bg-muted"
      role="progressbar"
      aria-valuenow={pct}
      aria-valuemin={0}
      aria-valuemax={100}
      data-status={status}
    >
      <div
        className="h-full rounded-full transition-all duration-500 ease-out"
        style={{ width: `${Math.min(100, pct)}%`, background: FILL[status] }}
      />
    </div>
  )
}
