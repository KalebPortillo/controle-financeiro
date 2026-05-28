import type { ReactNode } from 'react'

// Badge no padrão do design: altura 20px, radius-sm, variantes shadcn.
type Variant = 'default' | 'secondary' | 'outline' | 'destructive'

const VARIANTS: Record<Variant, string> = {
  default: 'bg-primary text-primary-foreground',
  secondary: 'bg-muted text-foreground',
  outline: 'bg-transparent text-foreground border border-border',
  destructive: 'bg-destructive text-destructive-foreground',
}

export function Badge({
  variant = 'default',
  children,
  className = '',
}: {
  variant?: Variant
  children: ReactNode
  className?: string
}) {
  return (
    <span
      className={`inline-flex items-center gap-1 h-5 px-2 rounded-sm text-[11px] font-medium leading-none ${VARIANTS[variant]} ${className}`}
    >
      {children}
    </span>
  )
}
