import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

// RF23 — desfaz um vínculo de transação relacionada (IOF/tarifa…).
export function useUnlinkTransaction() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (linkId: string) =>
      apiFetch(`/api/v1/transaction_links/${linkId}`, { method: 'DELETE' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['transactions'] }),
  })
}
