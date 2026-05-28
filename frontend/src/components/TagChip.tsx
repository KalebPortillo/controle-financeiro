// Chip de tag no padrão do design: dot de cor + nome, X opcional pra remover.
// Borda-radius pequeno (não pill), bg muted.

type Props = {
  name: string
  color?: string | null
  onRemove?: () => void
  className?: string
}

export function TagChip({ name, color, onRemove, className = '' }: Props) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 h-[22px] px-2 rounded-sm bg-muted text-foreground text-xs font-medium whitespace-nowrap shrink-0 ${className}`}
    >
      <span
        className="h-1.5 w-1.5 rounded-full shrink-0"
        style={{ background: color || 'var(--muted-foreground)' }}
      />
      {name}
      {onRemove && (
        <button
          type="button"
          onClick={onRemove}
          aria-label={`Remover ${name}`}
          className="ml-0.5 text-muted-foreground hover:text-destructive text-sm leading-none"
        >
          ×
        </button>
      )}
    </span>
  )
}
