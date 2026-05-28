import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

export type Tag = {
  id: string
  name: string
  color: string | null
  icon: string | null
  usage_count: number
}

export const tagsKey = ['tags'] as const

// Lista todas as tags do workspace (com usage_count). O autocomplete filtra no
// cliente a partir dessa lista — barato pro volume de um casal.
export function useTags() {
  return useQuery({
    queryKey: tagsKey,
    queryFn: () => apiFetch<{ tags: Tag[] }>('/api/v1/tags').then((r) => r.tags),
  })
}

// Cria uma tag nova (RF5.1).
export function useCreateTag() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (name: string) =>
      apiFetch<{ tag: Tag }>('/api/v1/tags', { method: 'POST', body: { name } }).then((r) => r.tag),
    onSuccess: () => qc.invalidateQueries({ queryKey: tagsKey }),
  })
}
