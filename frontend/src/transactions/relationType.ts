import type { RelatedItem } from './useInbox'

// Rótulos PT-BR dos tipos de vínculo (RF23), sentence case, sem ponto final.
export const RELATION_LABEL: Record<RelatedItem['relation_type'], string> = {
  iof: 'IOF',
  fee: 'Tarifa',
  interest: 'Juros',
  adjustment: 'Ajuste',
  refund: 'Estorno',
}

// Resumo dos satélites pro subtítulo do grupo: tipos distintos na ordem de
// aparição, ex.: "IOF" ou "IOF, Tarifa".
export function satelliteSummary(types: RelatedItem['relation_type'][]): string {
  const seen: string[] = []
  for (const t of types) {
    const label = RELATION_LABEL[t]
    if (!seen.includes(label)) seen.push(label)
  }
  return seen.join(', ')
}

// Resumo a partir dos satélites REALMENTE no grupo (mapa id→tipo), pulando os
// sem tipo. Usado pela linha/detalhe do grupo (inbox + consolidado).
export function groupSummary(
  satellites: { id: string }[],
  types: Map<string, RelatedItem['relation_type']>,
): string {
  return satelliteSummary(satellites.flatMap((s) => (types.get(s.id) ? [types.get(s.id)!] : [])))
}
