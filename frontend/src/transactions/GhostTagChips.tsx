import { Plus } from 'lucide-react'
import { useSuggestedTags, useAcceptSuggestedTag } from './useSuggestedTags'

/**
 * Chips "fantasma" (RF3/RF22) — tags que a IA sugeriu para esta transação mas
 * que ainda NÃO foram aceitas (ficam no catálogo suggested_tags, não em tags
 * reais). Visual tracejado/apagado pra distinguir das tags aplicadas. Clicar
 * aceita a sugestão (vira tag real) e a aplica nesta transação.
 *
 * Casa os nomes sugeridos da transação (ai_suggestion.new_tags) com as entradas
 * pendentes do catálogo — só mostra o que ainda dá pra aceitar.
 */
export function GhostTagChips({
  transactionId,
  suggestedNames,
}: {
  transactionId: string
  suggestedNames: string[]
}) {
  const { data: catalog } = useSuggestedTags()
  const accept = useAcceptSuggestedTag()

  if (suggestedNames.length === 0) return null

  const wanted = new Set(suggestedNames.map((n) => n.toLowerCase()))
  const chips = (catalog ?? []).filter((s) => wanted.has(s.name.toLowerCase()))
  if (chips.length === 0) return null

  return (
    <div className="flex flex-wrap gap-1.5" data-testid="ghost-tag-chips">
      {chips.map((s) => (
        <button
          key={s.id}
          type="button"
          onClick={() => accept.mutate({ id: s.id, transactionId })}
          disabled={accept.isPending}
          data-testid={`ghost-chip-${s.id}`}
          title={s.rationale ?? 'Sugerida pela IA'}
          className="inline-flex items-center gap-1 rounded-sm border border-dashed border-accent/50 bg-accent/5 px-2 py-0.5 text-[12px] text-accent hover:bg-accent/10 disabled:opacity-50"
        >
          <Plus size={11} />
          {s.name}
        </button>
      ))}
    </div>
  )
}
