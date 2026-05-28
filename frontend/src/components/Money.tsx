// Dinheiro no padrão do design system: monospace, tabular-nums, R$ 1.234,56.
// Negativo usa − (em-dash), não '-'. Em modo `signed`, positivos (receitas)
// ganham verde vívido; negativos ficam neutros (o app é majoritariamente gastos).

type Props = {
  cents: number
  signed?: boolean
  className?: string
}

function formatAbs(cents: number): string {
  return (Math.abs(cents) / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  })
}

export function Money({ cents, signed = false, className = '' }: Props) {
  const positive = cents > 0
  const negative = cents < 0
  const sign = signed ? (positive ? '+ ' : negative ? '− ' : '') : negative ? '− ' : ''
  const color = signed && positive ? 'text-[var(--success-vivid)]' : ''
  return (
    <span className={`cf-money ${color} ${className}`} style={{ whiteSpace: 'nowrap' }}>
      {sign}
      {formatAbs(cents)}
    </span>
  )
}
