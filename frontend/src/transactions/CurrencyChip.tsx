import { Badge } from '../components/Badge'

/**
 * Sinaliza no card que a compra foi em moeda estrangeira. O valor já está
 * convertido pra BRL (o banco converte); o chip mostra a moeda ORIGINAL
 * (ex.: "USD"). Nada quando a compra foi na moeda da conta.
 */
export function CurrencyChip({ currency }: { currency: string | null }) {
  if (!currency) return null
  return (
    <Badge variant="outline" className="shrink-0 tabular-nums">
      {currency}
    </Badge>
  )
}
