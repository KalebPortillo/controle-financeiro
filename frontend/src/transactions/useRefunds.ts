import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'
import type { InboxTransaction } from './useInbox'

// RF10 — candidatos a estorno de uma transação credit (débitos compatíveis).
export function useRefundCandidates(creditId: string, enabled: boolean) {
  return useQuery({
    queryKey: ['refund_candidates', creditId],
    enabled,
    queryFn: () =>
      apiFetch<{ refund_candidates: InboxTransaction[] }>(
        `/api/v1/transactions/${creditId}/refund_candidates`,
      ).then((r) => r.refund_candidates),
  })
}

// RF10 — vincula o estorno (credit) ao gasto escolhido.
export function useLinkRefund() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: { creditId: string; refundedTransactionId: string }) =>
      apiFetch(`/api/v1/transactions/${input.creditId}/link_refund`, {
        method: 'POST',
        body: { refunded_transaction_id: input.refundedTransactionId },
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['transactions'] }),
  })
}

// RF10 — desfaz um vínculo de estorno.
export function useUnlinkRefund() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (refundId: string) =>
      apiFetch(`/api/v1/transaction_refunds/${refundId}`, { method: 'DELETE' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['transactions'] }),
  })
}
