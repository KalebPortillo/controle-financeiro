import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'
import type { InboxTag } from './useInbox'

export type Category = {
  id: string
  name: string
  color: string | null
  icon: string | null
  tags: InboxTag[]
}

export const categoriesKey = ['categories'] as const

export function useCategories() {
  return useQuery({
    queryKey: categoriesKey,
    queryFn: () => apiFetch<{ categories: Category[] }>('/api/v1/categories').then((r) => r.categories),
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
