import { TriangleAlert } from 'lucide-react'
import { Badge } from '../components/Badge'

/**
 * Sinaliza uma linha de "ajuste" injetada pelo agregador (Pluggy) pra reconciliar
 * o saldo — NÃO é uma compra sua e não aparece no app do banco. Ajuda o usuário a
 * não consolidar por engano (inflaria o gasto). Ver Transactions::AggregatorAdjustment.
 */
export function AggregatorAdjustmentBadge({ show }: { show?: boolean }) {
  if (!show) return null
  return (
    <Badge variant="outline" className="shrink-0 gap-1 text-warning border-warning/40">
      <TriangleAlert size={11} /> ajuste de agregador
    </Badge>
  )
}
