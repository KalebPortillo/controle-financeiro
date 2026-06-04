import { Sparkles } from 'lucide-react'
import {
  useSuggestedTags,
  useAcceptSuggestedTag,
  useDismissSuggestedTag,
  type SuggestedTag,
} from './useSuggestedTags'
import { SuggestionRow } from './SuggestionRow'

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

function tagMeta(s: SuggestedTag) {
  const parts: string[] = []
  if (s.coverage > 0) parts.push(`${s.coverage} ${s.coverage === 1 ? 'gasto' : 'gastos'}`)
  if (s.rationale) parts.push(s.rationale)
  return parts.length > 0 ? parts.join(' · ') : undefined
}

function SuggestedTagRow({ suggestion }: { suggestion: SuggestedTag }) {
  const accept = useAcceptSuggestedTag()
  const dismiss = useDismissSuggestedTag()

  return (
    <SuggestionRow
      id={suggestion.id}
      name={suggestion.name}
      meta={tagMeta(suggestion)}
      onAccept={() => accept.mutate({ id: suggestion.id })}
      onDismiss={() => dismiss.mutate(suggestion.id)}
      disabled={accept.isPending || dismiss.isPending}
      testidPrefix="suggested-tag"
      acceptTestid={`accept-suggestion-${suggestion.id}`}
      dismissTestid={`dismiss-suggestion-${suggestion.id}`}
    />
  )
}
