import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'
import type { InboxTransaction, RelatedItem } from './useInbox'

// RF23 — desfaz um vínculo de transação relacionada (IOF/tarifa…).
export function useUnlinkTransaction() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (linkId: string) =>
      apiFetch(`/api/v1/transaction_links/${linkId}`, { method: 'DELETE' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['transactions'] }),
  })
}

// RF23 Fase 3 — candidatos de origem pra vínculo manual de um satélite (:id).
// Busca opcional (?q). Lazy: só busca quando o picker está aberto.
export function useLinkCandidates(id: string, q: string, enabled: boolean) {
  const query = q.trim()
  return useQuery({
    queryKey: ['link_candidates', id, query],
    enabled,
    queryFn: () =>
      apiFetch<{ link_candidates: InboxTransaction[] }>(
        `/api/v1/transactions/${id}/link_candidates${query ? `?q=${encodeURIComponent(query)}` : ''}`,
      ).then((r) => r.link_candidates),
  })
}

export type LinkInput = {
  id: string // satélite
  origin_id: string
  relation_type: RelatedItem['relation_type']
}

// RF23 Fase 3 — vincula manualmente o satélite (:id) a um gasto de origem.
export function useLinkTransaction() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, origin_id, relation_type }: LinkInput) =>
      apiFetch<{ transaction: InboxTransaction }>(`/api/v1/transactions/${id}/link`, {
        method: 'POST',
        body: { origin_id, relation_type },
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['transactions'] }),
  })
}
