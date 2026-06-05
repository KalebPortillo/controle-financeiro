import type { ReactNode } from 'react'
import { AlertTriangle, Info } from 'lucide-react'

// Aviso inline para estados de erro PERSISTENTES (ex.: IA indisponível) — ao
// contrário do toast efêmero. Bordas, não sombras (design system); ícone Lucide.
type Variant = 'destructive' | 'warning' | 'info'

const VARIANTS: Record<Variant, { box: string; icon: string }> = {
  destructive: { box: 'border-destructive/30 bg-destructive/10', icon: 'text-destructive' },
  warning:     { box: 'border-warning/30 bg-warning/10',         icon: 'text-warning' },
  info:        { box: 'border-border bg-muted',                  icon: 'text-muted-foreground' },
}

const ICONS: Record<Variant, typeof AlertTriangle> = {
  destructive: AlertTriangle,
  warning:     AlertTriangle,
  info:        Info,
}

export function Alert({
  variant = 'destructive',
  title,
  children,
  action,
  className = '',
  testid,
}: {
  variant?: Variant
  title: string
  children?: ReactNode
  action?: ReactNode
  className?: string
  testid?: string
}) {
  const v = VARIANTS[variant]
  const Icon = ICONS[variant]
  return (
    <div
      role="alert"
      data-testid={testid}
      className={`flex items-start gap-3 rounded-lg border px-4 py-3 ${v.box} ${className}`}
    >
      <Icon size={16} className={`mt-0.5 shrink-0 ${v.icon}`} />
      <div className="min-w-0 flex-1 space-y-1">
        <p className="text-sm font-medium">{title}</p>
        {children && <div className="text-xs text-muted-foreground">{children}</div>}
        {action && <div className="pt-1">{action}</div>}
      </div>
    </div>
  )
}
