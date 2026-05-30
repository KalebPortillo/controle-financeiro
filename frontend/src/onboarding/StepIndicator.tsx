import { Check } from 'lucide-react'

export type Step = { id: string; label: string }

/**
 * Indicador de progresso usado no fluxo de onboarding (RF22).
 * Linha de círculos conectados. Atual = accent cheio; passado = check;
 * futuro = vazio com borda.
 */
export function StepIndicator({
  steps,
  current,
}: {
  steps: readonly Step[]
  current: number // 1-based — qual passo está ativo
}) {
  return (
    <ol
      className="flex items-center gap-0 select-none"
      role="list"
      data-testid="step-indicator"
    >
      {steps.map((step, idx) => {
        const number = idx + 1
        const isPast = number < current
        const isActive = number === current
        const isFuture = number > current

        return (
          <li key={step.id} className="flex items-center gap-2 flex-1 last:flex-none">
            <div className="flex items-center gap-2 min-w-0">
              <span
                className={[
                  'inline-flex h-6 w-6 items-center justify-center rounded-full text-[11px] font-semibold shrink-0',
                  isActive && 'bg-accent text-accent-foreground',
                  isPast   && 'border border-accent text-accent',
                  isFuture && 'border border-border text-muted-foreground',
                ].filter(Boolean).join(' ')}
                aria-current={isActive ? 'step' : undefined}
              >
                {isPast ? <Check size={12} aria-hidden /> : number}
              </span>
              <span
                className={[
                  'text-[11px] font-medium truncate',
                  isActive ? 'text-foreground' : 'text-muted-foreground',
                ].join(' ')}
              >
                {step.label}
              </span>
            </div>
            {idx < steps.length - 1 && (
              <span
                className={[
                  'flex-1 h-px',
                  number < current ? 'bg-accent' : 'bg-border',
                ].join(' ')}
                aria-hidden
              />
            )}
          </li>
        )
      })}
    </ol>
  )
}
