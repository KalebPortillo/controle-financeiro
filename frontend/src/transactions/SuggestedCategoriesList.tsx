import { Sparkles } from 'lucide-react'
import {
  useAcceptSuggestedCategory,
  useDismissSuggestedCategory,
  type SuggestedCategory,
} from './useSuggestedCategories'
import { SuggestionRow } from './SuggestionRow'

/**
 * Seção "Sugeridas pela IA" das categorias (RF22, 2ª análise). Recebe a lista
 * por prop (o passo de categorias já a busca pra decidir a tela de espera).
 * Aceitar cria a Category real e associa as tags; recusar a remove.
 */
export function SuggestedCategoriesList({ suggestions }: { suggestions: SuggestedCategory[] }) {
  if (suggestions.length === 0) return null
  return (
    <section className="space-y-2" data-testid="suggested-categories-section">
      <div className="flex items-center gap-1.5">
        <Sparkles size={14} className="text-accent" />
        <h2 className="text-sm font-medium">Sugeridas pela IA</h2>
      </div>
      <p className="text-xs text-muted-foreground">
        A IA agrupou suas tags aceitas. Aceite para virar uma categoria de verdade.
      </p>
      <div className="border border-border rounded-lg overflow-hidden">
        {suggestions.map((s) => (
          <SuggestedCategoryRow key={s.id} suggestion={s} />
        ))}
      </div>
    </section>
  )
}

function SuggestedCategoryRow({ suggestion }: { suggestion: SuggestedCategory }) {
  const accept = useAcceptSuggestedCategory()
  const dismiss = useDismissSuggestedCategory()

  return (
    <SuggestionRow
      id={suggestion.id}
      name={suggestion.name}
      meta={suggestion.tag_names.length > 0 ? suggestion.tag_names.join(', ') : undefined}
      onAccept={() => accept.mutate({ id: suggestion.id })}
      onDismiss={() => dismiss.mutate(suggestion.id)}
      disabled={accept.isPending || dismiss.isPending}
      testidPrefix="suggested-category"
      acceptTestid={`accept-suggested-category-${suggestion.id}`}
      dismissTestid={`dismiss-suggested-category-${suggestion.id}`}
    />
  )
}
