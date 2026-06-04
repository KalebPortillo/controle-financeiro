import { Check, X, Sparkles } from 'lucide-react'
import { Button } from '../components/Button'
import {
  useSuggestedTags,
  useAcceptSuggestedTag,
  useDismissSuggestedTag,
  type SuggestedTag,
} from './useSuggestedTags'

/**
 * Seção "Sugeridas pela IA" (RF3/RF22) — catálogo de tags sugeridas, separado das
 * tags reais. Aceitar promove a Tag de verdade; recusar a remove. Reutilizada na
 * página Tags e na etapa de tags do onboarding. Só renderiza se houver sugestões.
 */
export function SuggestedTagsList() {
  const { data: suggestions } = useSuggestedTags()
  if (!suggestions || suggestions.length === 0) return null

  return (
    <section className="space-y-2" data-testid="suggested-section">
      <div className="flex items-center gap-1.5">
        <Sparkles size={14} className="text-accent" />
        <h2 className="text-sm font-medium">Sugeridas pela IA</h2>
      </div>
      <p className="text-xs text-muted-foreground">
        A IA detectou estes padrões nos seus gastos. Aceite para virar uma tag de verdade.
      </p>
      <div className="border border-border rounded-lg overflow-hidden">
        {suggestions.map((s) => (
          <SuggestedTagRow key={s.id} suggestion={s} />
        ))}
      </div>
    </section>
  )
}

function SuggestedTagRow({ suggestion }: { suggestion: SuggestedTag }) {
  const accept = useAcceptSuggestedTag()
  const dismiss = useDismissSuggestedTag()
  const busy = accept.isPending || dismiss.isPending

  return (
    <div
      className="px-4 py-3 border-b border-border last:border-b-0 flex items-center gap-3"
      data-testid={`suggested-tag-${suggestion.id}`}
    >
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium truncate">{suggestion.name}</span>
          {suggestion.coverage > 0 && (
            <span className="text-[11px] text-muted-foreground shrink-0">
              {suggestion.coverage} {suggestion.coverage === 1 ? 'gasto' : 'gastos'}
            </span>
          )}
        </div>
        {suggestion.rationale && (
          <p className="text-[11px] text-muted-foreground mt-0.5 truncate">{suggestion.rationale}</p>
        )}
      </div>
      <Button
        variant="outline"
        size="sm"
        onClick={() => accept.mutate({ id: suggestion.id })}
        disabled={busy}
        data-testid={`accept-suggestion-${suggestion.id}`}
      >
        <Check size={14} /> Aceitar
      </Button>
      <Button
        variant="ghost"
        size="sm"
        onClick={() => dismiss.mutate(suggestion.id)}
        disabled={busy}
        aria-label={`Recusar ${suggestion.name}`}
        data-testid={`dismiss-suggestion-${suggestion.id}`}
      >
        <X size={14} />
      </Button>
    </div>
  )
}
