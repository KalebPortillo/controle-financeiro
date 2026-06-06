import {
  useAcceptSuggestedCategory,
  useDismissSuggestedCategory,
  type SuggestedCategory,
} from './useSuggestedCategories'
import { SuggestionRow } from './SuggestionRow'

/**
 * Lista das categorias sugeridas pela IA (RF6/RF22). A seção/título é da página;
 * aqui só renderiza as linhas. Aceitar cria a Category real e associa as tags;
 * recusar a remove.
 */
export function SuggestedCategoriesList({ suggestions }: { suggestions: SuggestedCategory[] }) {
  if (suggestions.length === 0) return null
  return (
    <div className="border border-border rounded-lg overflow-hidden" data-testid="suggested-categories-section">
      {suggestions.map((s) => (
        <SuggestedCategoryRow key={s.id} suggestion={s} />
      ))}
    </div>
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
