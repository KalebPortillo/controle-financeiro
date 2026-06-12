import { CircleSlash } from 'lucide-react'
import type { AiConfidence } from './useInbox'

// Selo de confiança da sugestão da IA (RF3). Sóbrio, borda + cor leve.
export function AiConfidenceBadge({ confidence }: { confidence: AiConfidence }) {
  if (!confidence) return null
  const styles: Record<NonNullable<AiConfidence>, string> = {
    high:   'bg-green-50 text-green-700 border-green-200',
    medium: 'bg-yellow-50 text-yellow-700 border-yellow-200',
    low:    'bg-red-50 text-red-700 border-red-200',
  }
  const labels: Record<NonNullable<AiConfidence>, string> = { high: 'IA', medium: 'IA?', low: 'IA?' }
  return (
    <span className={`inline-flex items-center rounded-sm border px-1 py-0 text-[10px] font-medium ${styles[confidence]}`}>
      {labels[confidence]}
    </span>
  )
}

// Chip "não analisado" — a IA não conseguiu (ai_status failed).
export function NotAnalyzedBadge({ id }: { id: string }) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-sm border border-warning/40 bg-warning/10 px-1 py-0 text-[10px] font-medium text-warning"
      data-testid={`not-analyzed-${id}`}
      title="A IA não conseguiu analisar este gasto"
    >
      <CircleSlash size={10} /> não analisado
    </span>
  )
}
