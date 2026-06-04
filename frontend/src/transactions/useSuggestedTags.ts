import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'
import { tagsKey } from './useTags'

// Tag sugerida pela IA (RF3/RF22), ainda não aceita. Catálogo separado das tags
// reais — vira Tag de verdade só quando aceita. Ver suggested_tags no backend.
export type SuggestedTag = {
  id: string
  name: string
  rationale: string | null
  coverage: number
  source: 'detected' | 'manual' | 'inbox'
  status: 'pending' | 'accepted' | 'dismissed'
}

export const suggestedTagsKey = ['suggested_tags'] as const

export function useSuggestedTags() {
  return useQuery({
    queryKey: suggestedTagsKey,
    queryFn: () =>
      apiFetch<{ suggested_tags: SuggestedTag[] }>('/api/v1/suggested_tags').then(
        (r) => r.suggested_tags,
      ),
  })
}

// Aceita a sugestão → cria a Tag real (ou reusa de mesmo nome) e marca accepted.
// Opcionalmente aplica a tag a uma transação (caminho do chip fantasma da inbox).
export function useAcceptSuggestedTag() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: { id: string; transactionId?: string }) =>
      apiFetch(`/api/v1/suggested_tags/${input.id}/accept`, {
        method: 'POST',
        body: input.transactionId ? { transaction_id: input.transactionId } : undefined,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: suggestedTagsKey })
      qc.invalidateQueries({ queryKey: tagsKey })
    },
  })
}

// Recusa a sugestão (status dismissed) — some da lista.
export function useDismissSuggestedTag() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) =>
      apiFetch(`/api/v1/suggested_tags/${id}`, { method: 'DELETE' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: suggestedTagsKey }),
  })
}
