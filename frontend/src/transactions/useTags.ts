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

// Edita nome/cor de uma tag (RF5.4).
export function useUpdateTag() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: { id: string; name?: string; color?: string | null }) =>
      apiFetch<{ tag: Tag }>(`/api/v1/tags/${input.id}`, {
        method: 'PATCH',
        body: { name: input.name, color: input.color },
      }).then((r) => r.tag),
    onSuccess: () => qc.invalidateQueries({ queryKey: tagsKey }),
  })
}

// Mescla a tag origem na destino (RF5.4). Move as relações e apaga a origem.
export function useMergeTag() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: { id: string; intoTagId: string }) =>
      apiFetch(`/api/v1/tags/${input.id}/merge`, {
        method: 'POST',
        body: { into_tag_id: input.intoTagId },
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: tagsKey }),
  })
}

// Exclui uma tag (RF5.4). 422 tag_in_use se aplicada a alguma transação.
export function useDeleteTag() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => apiFetch(`/api/v1/tags/${id}`, { method: 'DELETE' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: tagsKey }),
  })
}
