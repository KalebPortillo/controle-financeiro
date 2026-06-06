import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'
import type { InboxTag } from './useInbox'
import type { AiError } from './useSuggestedCategories'

export type Category = {
  id: string
  name: string
  color: string | null
  icon: string | null
  tags: InboxTag[]
  // Tags JÁ existentes sugeridas pela IA pra entrar na categoria (RF6). O `id`
  // de cada uma é o id da TAG (chave do accept/dismiss).
  tag_suggestions: InboxTag[]
}

type CategoriesPayload = { categories: Category[]; ai_error: AiError | null }

export const categoriesKey = ['categories'] as const

// `poll` repete a cada 2s enquanto uma geração de tag-sugestões está em curso.
export function useCategories({ poll = false } = {}) {
  return useQuery({
    queryKey: categoriesKey,
    queryFn: () => apiFetch<CategoriesPayload>('/api/v1/categories'),
    refetchInterval: () => (poll ? 2000 : false),
  })
}

function useCategoryMutation<TInput>(fn: (input: TInput) => Promise<unknown>) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: fn,
    onSuccess: () => qc.invalidateQueries({ queryKey: categoriesKey }),
  })
}

export function useCreateCategory() {
  return useCategoryMutation((input: { name: string; color?: string | null; tag_ids?: string[] }) =>
    apiFetch('/api/v1/categories', { method: 'POST', body: input })
  )
}

export function useUpdateCategory() {
  return useCategoryMutation((input: { id: string; name?: string; color?: string | null; tag_ids?: string[] }) =>
    apiFetch(`/api/v1/categories/${input.id}`, {
      method: 'PATCH',
      body: { name: input.name, color: input.color, tag_ids: input.tag_ids },
    })
  )
}

export function useMergeCategory() {
  return useCategoryMutation((input: { id: string; intoCategoryId: string }) =>
    apiFetch(`/api/v1/categories/${input.id}/merge`, {
      method: 'POST',
      body: { into_category_id: input.intoCategoryId },
    })
  )
}

export function useDeleteCategory() {
  return useCategoryMutation((id: string) =>
    apiFetch(`/api/v1/categories/${id}`, { method: 'DELETE' })
  )
}

// --- Tags sugeridas por categoria (RF6) ---

// Dispara a geração on-demand (202, assíncrono) das tags faltantes da categoria.
export function useSuggestCategoryTags() {
  return useCategoryMutation((categoryId: string) =>
    apiFetch(`/api/v1/categories/${categoryId}/suggest_tags`, { method: 'POST' })
  )
}

// Aceita uma tag sugerida → adiciona à categoria.
export function useAcceptCategoryTagSuggestion() {
  return useCategoryMutation((input: { categoryId: string; tagId: string }) =>
    apiFetch(`/api/v1/categories/${input.categoryId}/tag_suggestions/${input.tagId}/accept`, { method: 'POST' })
  )
}

// Recusa uma tag sugerida (dismissed).
export function useDismissCategoryTagSuggestion() {
  return useCategoryMutation((input: { categoryId: string; tagId: string }) =>
    apiFetch(`/api/v1/categories/${input.categoryId}/tag_suggestions/${input.tagId}`, { method: 'DELETE' })
  )
}
