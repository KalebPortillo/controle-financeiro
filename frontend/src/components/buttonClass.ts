type Variant = 'primary' | 'outline' | 'ghost' | 'destructive'
type Size    = 'sm' | 'md' | 'lg'

const base =
  'inline-flex items-center justify-center gap-2 rounded-md font-sans font-medium ' +
  'transition-colors disabled:opacity-50 disabled:cursor-not-allowed ' +
  'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 ' +
  'focus-visible:outline-ring whitespace-nowrap'

const sizes: Record<Size, string> = {
  sm: 'h-7 px-2.5 text-xs',
  md: 'h-8 px-3  text-[13px]',
  lg: 'h-10 px-4 text-sm',
}

const variants: Record<Variant, string> = {
  primary:
    'bg-primary text-primary-foreground hover:bg-primary/90',
  outline:
    'bg-transparent text-foreground border border-input hover:bg-muted',
  ghost:
    'bg-transparent text-foreground hover:bg-muted',
  destructive:
    'bg-destructive text-destructive-foreground hover:bg-destructive/90',
}

/**
 * Retorna a classe equivalente ao Button — útil quando você precisa estilizar
 * outro elemento (ex.: `<a>`) com o mesmo visual. HTML manda que <button>
 * não pode conter <a>, então pra ações que navegam (login, links externos)
 * usamos `<a className={buttonClass(...)}>`.
 *
 * Vive em arquivo próprio (não em Button.tsx) pra não quebrar o
 * react-refresh, que exige que arquivos de componente só exportem componentes.
 */
export function buttonClass({
  variant = 'primary',
  size    = 'md',
  className = '',
}: { variant?: Variant; size?: Size; className?: string } = {}) {
  return `${base} ${sizes[size]} ${variants[variant]} ${className}`
}

export type { Variant as ButtonVariant, Size as ButtonSize }
