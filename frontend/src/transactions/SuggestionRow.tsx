import type { ReactNode } from 'react'
import { Check, X } from 'lucide-react'
import { Button } from '../components/Button'

/**
 * Linha genérica de uma sugestão da IA (RF3/RF22) — usada por tags e categorias.
 * Mostra nome + uma linha de meta (rationale/coverage para tags, tags-membros
 * para categorias) e os botões Aceitar / Recusar. `testidPrefix` distingue os
 * dois usos (ex.: "suggested-tag" → suggested-tag-<id>, accept-suggestion-<id>).
 */
export function SuggestionRow({
  id,
  name,
  meta,
  onAccept,
  onDismiss,
  disabled,
  testidPrefix,
  acceptTestid,
  dismissTestid,
}: {
  id: string
  name: string
  meta?: ReactNode
  onAccept: () => void
  onDismiss: () => void
  disabled: boolean
  testidPrefix: string
  acceptTestid: string
  dismissTestid: string
}) {
  return (
    <div
      className="px-4 py-3 border-b border-border last:border-b-0 flex items-center gap-3"
      data-testid={`${testidPrefix}-${id}`}
    >
      <div className="flex-1 min-w-0">
        <span className="text-sm font-medium truncate">{name}</span>
        {meta && <div className="text-[11px] text-muted-foreground mt-0.5 truncate">{meta}</div>}
      </div>
      <Button
        variant="outline"
        size="sm"
        onClick={onAccept}
        disabled={disabled}
        data-testid={acceptTestid}
      >
        <Check size={14} /> Aceitar
      </Button>
      <Button
        variant="ghost"
        size="sm"
        onClick={onDismiss}
        disabled={disabled}
        aria-label={`Recusar ${name}`}
        data-testid={dismissTestid}
      >
        <X size={14} />
      </Button>
    </div>
  )
}
