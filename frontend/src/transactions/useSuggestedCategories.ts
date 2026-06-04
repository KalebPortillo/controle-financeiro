import { categoriesKey } from './useCategories'
import { makeSuggestionHooks } from './makeSuggestionHooks'

// Categoria sugerida pela IA (RF22, 2ª análise), ainda não aceita. Catálogo
// separado das categorias reais — vira Category de verdade só quando aceita.
export type SuggestedCategory = {
  id: string
  name: string
  tag_names: string[]
  status: 'pending' | 'accepted' | 'dismissed'
}

export const suggestedCategoriesKey = ['suggested_categories'] as const

const hooks = makeSuggestionHooks<SuggestedCategory, { id: string }>({
  resource: 'suggested_categories',
  responseKey: 'suggested_categories',
  queryKey: suggestedCategoriesKey,
  invalidateOnAccept: [categoriesKey],
})

// `pollWhileEmpty` faz a query repetir a cada 3s enquanto a lista volta vazia —
// usado no onboarding, onde a 2ª análise (SuggestCategoriesJob) ainda pode estar
// rodando e as sugestões aparecem depois.
export const useSuggestedCategories = hooks.useList
// Aceita a sugestão → cria a Category real (ou reusa de mesmo nome) e associa as
// tags por nome. Marca accepted.
export const useAcceptSuggestedCategory = hooks.useAccept
// Recusa a sugestão (status dismissed) — some da lista.
export const useDismissSuggestedCategory = hooks.useDismiss
