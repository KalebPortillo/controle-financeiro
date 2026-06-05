import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

export type InboxTag = {
  id: string
  name: string
  color: string | null
  icon: string | null
}

export type AiConfidence = 'high' | 'medium' | 'low' | null

export type AiSuggestion = {
  title: string | null
  tag_ids: string[]
  tag_names: string[]
  new_tags: string[]
  confidence: AiConfidence
  source: string
  suggested_at: string
} | null

// RF10 — resumo dos estornos recebidos por um gasto (null se nenhum).
export type RefundInfo = {
  refunded_amount_cents: number
  refunds: Array<{
    id: string
    refund_transaction_id: string
    amount_cents: number
    confirmed_at: string
  }>
} | null

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
  ai_confidence: AiConfidence
  ai_suggestion: AiSuggestion
  status: string
  source: string
  lock_version: number
  tags: InboxTag[]
  // RF10 — valor efetivo (amount menos estornos) + resumo dos estornos.
  effective_amount_cents: number
  refund: RefundInfo
}

export type InboxPayload = {
  transactions: InboxTransaction[]
  pending_count: number
}

// Prefixo comum: invalidar ['transactions'] recarrega inbox E consolidados,
// já que uma ação (aceitar/editar/remover) pode mover a transação entre eles.
const transactionsKey = ['transactions'] as const
export const inboxKey = ['transactions', 'pending'] as const
export const consolidatedKey = (period: string) => ['transactions', 'consolidated', period] as const

// Lista as transações pendentes (RF2.1/2.4). Inclui pending_count pro badge.
export function useInbox() {
  return useQuery({
    queryKey: inboxKey,
    queryFn: () => apiFetch<InboxPayload>('/api/v1/transactions?status=pending'),
  })
}

// Lista consolidados de um mês (RF4). `period` = 'YYYY-MM'.
export function useConsolidated(period: string) {
  const [year, month] = period.split('-').map(Number)
  const from = `${period}-01`
  const to = new Date(year, month, 0).toISOString().slice(0, 10) // último dia do mês
  return useQuery({
    queryKey: consolidatedKey(period),
    queryFn: () =>
      apiFetch<InboxPayload>(
        `/api/v1/transactions?status=consolidated&from=${from}&to=${to}`
      ),
  })
}

function useInboxMutation<TInput>(
  fn: (input: TInput) => Promise<unknown>
) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: fn,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: transactionsKey })
      qc.invalidateQueries({ queryKey: ['transaction_edits'] }) // RF4.3: histórico reflete a edição
    },
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

export type ManualEntryInput = {
  direction: 'debit' | 'credit'
  amount_cents: number
  occurred_at: string
  improved_title?: string
  tag_ids?: string[]
}

// Lançar gasto/receita manual (RF12) — vai direto pra consolidados.
export function useCreateManualTransaction() {
  return useInboxMutation((input: ManualEntryInput) =>
    apiFetch('/api/v1/transactions', { method: 'POST', body: input })
  )
}

// Reanalisar com IA (RF3.5) — enfileira job pra todas as transações pending.
export function useReanalyzeInbox() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => apiFetch<{ enqueued: boolean; pending_count: number }>(
      '/api/v1/transactions/reanalyze', { method: 'POST' }
    ),
    onSuccess: () => {
      // Após ~3s o job terá processado parte das sugestões; recarrega a inbox
      setTimeout(() => qc.invalidateQueries({ queryKey: transactionsKey }), 3000)
    },
  })
}

export type TransactionEdit = {
  id: string
  field_name: string
  old_value: unknown
  new_value: unknown
  edited_at: string
  edited_by: { id: string; name: string }
}

// Histórico de alterações de uma transação (RF4.3). `enabled` evita o fetch até
// a seção de histórico ser aberta.
export function useTransactionEdits(id: string, enabled: boolean) {
  return useQuery({
    queryKey: ['transaction_edits', id],
    enabled,
    queryFn: () =>
      apiFetch<{ edits: TransactionEdit[] }>(`/api/v1/transactions/${id}/edits`).then((r) => r.edits),
  })
}
