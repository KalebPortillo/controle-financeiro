import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'
import { categoriesKey } from './useCategories'
import { makeSuggestionHooks } from './makeSuggestionHooks'

// Categoria sugerida pela IA (RF6/RF22), ainda não aceita. Catálogo separado das
// categorias reais — vira Category de verdade só quando aceita.
export type SuggestedCategory = {
  id: string
  name: string
  tag_names: string[]
  status: 'pending' | 'accepted' | 'dismissed'
}

// Erro de IA exposto pela camada de feedback (mesmo formato no inbox/onboarding).
export type AiError = { reason: string; message: string; at: string }

export const suggestedCategoriesKey = ['suggested_categories'] as const

const hooks = makeSuggestionHooks<SuggestedCategory, { id: string }>({
  resource: 'suggested_categories',
  responseKey: 'suggested_categories',
  queryKey: suggestedCategoriesKey,
  invalidateOnAccept: [categoriesKey],
})

// Aceitar → cria a Category real (ou reusa de mesmo nome) e associa as tags por
// nome; invalida `categories` (some daqui e aparece nas consolidadas).
export const useAcceptSuggestedCategory = hooks.useAccept
// Recusar (status dismissed) — some da lista.
export const useDismissSuggestedCategory = hooks.useDismiss

type Payload = { suggested_categories: SuggestedCategory[]; ai_error: AiError | null }

// Lista as categorias sugeridas + o erro de IA. `poll` repete a cada 2s enquanto
// a geração (assíncrona) ainda não trouxe sugestões nem erro.
export function useSuggestedCategories({ poll = false } = {}) {
  const q = useQuery({
    queryKey: suggestedCategoriesKey,
    queryFn: () => apiFetch<Payload>('/api/v1/suggested_categories'),
    refetchInterval: () => (poll ? 2000 : false),
  })
  return {
    suggestions: q.data?.suggested_categories ?? [],
    error: q.data?.ai_error ?? null,
    isLoading: q.isLoading,
  }
}

// Dispara a geração on-demand (202, assíncrono). Recarrega a lista pra começar
// o polling.
export function useGenerateSuggestedCategories() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => apiFetch('/api/v1/suggested_categories/generate', { method: 'POST' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: suggestedCategoriesKey }),
  })
}
