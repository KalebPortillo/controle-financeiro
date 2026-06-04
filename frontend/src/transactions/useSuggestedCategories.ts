import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'
import { categoriesKey } from './useCategories'

// Categoria sugerida pela IA (RF22, 2ª análise), ainda não aceita. Catálogo
// separado das categorias reais — vira Category de verdade só quando aceita.
export type SuggestedCategory = {
  id: string
  name: string
  tag_names: string[]
  status: 'pending' | 'accepted' | 'dismissed'
}

export const suggestedCategoriesKey = ['suggested_categories'] as const

// `pollWhileEmpty` faz a query repetir a cada 3s enquanto a lista volta vazia —
// usado no onboarding, onde a 2ª análise (SuggestCategoriesJob) ainda pode estar
// rodando e as sugestões aparecem depois.
export function useSuggestedCategories({ pollWhileEmpty = false } = {}) {
  return useQuery({
    queryKey: suggestedCategoriesKey,
    queryFn: () =>
      apiFetch<{ suggested_categories: SuggestedCategory[] }>('/api/v1/suggested_categories').then(
        (r) => r.suggested_categories,
      ),
    refetchInterval: (query) =>
      pollWhileEmpty && (query.state.data?.length ?? 0) === 0 ? 3000 : false,
  })
}

// Aceita a sugestão → cria a Category real (ou reusa de mesmo nome) e associa as
// tags por nome. Marca accepted.
export function useAcceptSuggestedCategory() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) =>
      apiFetch(`/api/v1/suggested_categories/${id}/accept`, { method: 'POST' }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: suggestedCategoriesKey })
      qc.invalidateQueries({ queryKey: categoriesKey })
    },
  })
}

// Recusa a sugestão (status dismissed) — some da lista.
export function useDismissSuggestedCategory() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) =>
      apiFetch(`/api/v1/suggested_categories/${id}`, { method: 'DELETE' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: suggestedCategoriesKey }),
  })
}
