import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

export type InboxTag = {
  id: string
  name: string
  color: string | null
  icon: string | null
}

export type InboxTransaction = {
  id: string
  account_id: string
  account_name: string | null
  direction: 'debit' | 'credit'
  amount_cents: number
  currency: string
  occurred_at: string
  original_description: string
  improved_title: string | null
  status: string
  source: string
  lock_version: number
  tags: InboxTag[]
}

export type InboxPayload = {
  transactions: InboxTransaction[]
  pending_count: number
}

export const inboxKey = ['inbox'] as const

// Lista as transações pendentes (RF2.1/2.4). Inclui pending_count pro badge.
export function useInbox() {
  return useQuery({
    queryKey: inboxKey,
    queryFn: () => apiFetch<InboxPayload>('/api/v1/transactions?status=pending'),
  })
}

function useInboxMutation<TInput>(
  fn: (input: TInput) => Promise<unknown>
) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: fn,
    onSuccess: () => qc.invalidateQueries({ queryKey: inboxKey }),
  })
}

// Aceitar (RF2.3).
export function useConsolidate() {
  return useInboxMutation((id: string) =>
    apiFetch(`/api/v1/transactions/${id}/consolidate`, { method: 'POST' })
  )
}

// Rejeitar (RF2.3).
export function useReject() {
  return useInboxMutation((id: string) =>
    apiFetch(`/api/v1/transactions/${id}/reject`, { method: 'POST' })
  )
}

// Remover (RF2.3) — exclusão definitiva.
export function useRemoveTransaction() {
  return useInboxMutation((id: string) =>
    apiFetch(`/api/v1/transactions/${id}`, { method: 'DELETE' })
  )
}

export type UpdateInput = {
  id: string
  lock_version: number
  improved_title?: string
  amount_cents?: number
  occurred_at?: string
  tag_ids?: string[]
}

// Editar título/valor/data (RF2.3) com optimistic lock.
export function useUpdateTransaction() {
  return useInboxMutation(({ id, ...body }: UpdateInput) =>
    apiFetch(`/api/v1/transactions/${id}`, { method: 'PATCH', body })
  )
}
