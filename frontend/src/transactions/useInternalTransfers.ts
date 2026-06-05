import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

// RF11 — par de transferência interna (saída + entrada entre contas próprias).
export type InternalTransfer = {
  id: string
  manual: boolean
  detected_at: string
  debit: TransferLeg
  credit: TransferLeg
}

export type TransferLeg = {
  id: string
  account_name: string | null
  amount_cents: number
  occurred_at: string
  title: string
}

export const internalTransfersKey = ['internal_transfers'] as const

export function useInternalTransfers() {
  return useQuery({
    queryKey: internalTransfersKey,
    queryFn: () =>
      apiFetch<{ internal_transfers: InternalTransfer[] }>('/api/v1/internal_transfers').then(
        (r) => r.internal_transfers,
      ),
  })
}

// Marca manualmente um par como transferência interna (RF11.4).
export function useMarkInternalTransfer() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: { debitTransactionId: string; creditTransactionId: string }) =>
      apiFetch('/api/v1/internal_transfers', {
        method: 'POST',
        body: {
          debit_transaction_id: input.debitTransactionId,
          credit_transaction_id: input.creditTransactionId,
        },
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: internalTransfersKey })
      qc.invalidateQueries({ queryKey: ['transactions'] })
    },
  })
}

// Desmarca (RF11.4) — a saída/entrada voltam a contar como gasto/receita.
export function useUnmarkInternalTransfer() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) =>
      apiFetch(`/api/v1/internal_transfers/${id}`, { method: 'DELETE' }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: internalTransfersKey })
      qc.invalidateQueries({ queryKey: ['transactions'] })
    },
  })
}
