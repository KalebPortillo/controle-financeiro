import { Layers } from 'lucide-react'

/**
 * Indicador de parcela (RF9.4): "3/12" com ícone, ligando visualmente as
 * parcelas do mesmo parcelamento. Some quando não há total.
 */
export function InstallmentBadge({
  number,
  total,
}: {
  number: number | null
  total: number | null
}) {
  if (!total) return null

  return (
    <span
      className="inline-flex items-center gap-1 text-[11px] text-muted-foreground"
      data-testid="installment-badge"
      title="Compra parcelada"
    >
      <Layers size={11} className="shrink-0" />
      {number ?? '?'}/{total}
    </span>
  )
}
