import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

// Contrato real (contratos-api.md + RecurrencesController):
//   GET   /api/v1/recurrences            → { recurrences: [...] }
//   PATCH /api/v1/recurrences/:id  (body flat) → { recurrence: {...} }
// Campos do serializer: id, account_id, descriptor_pattern,
// expected_amount_cents, amount_tolerance_pct, cadence, next_expected_at,
// status, source.

export type Cadence = 'weekly' | 'monthly' | 'yearly' | 'custom'
export type RecurrenceStatus = 'active' | 'paused' | 'cancelled'
export type RecurrenceSource = 'detected' | 'manual'

export type Recurrence = {
  id: string
  account_id: string
  descriptor_pattern: string
  expected_amount_cents: number | null
  amount_tolerance_pct: number
  cadence: Cadence
  next_expected_at: string | null
  status: RecurrenceStatus
  source: RecurrenceSource
}

export const recurrencesKey = ['recurrences'] as const

export function useRecurrences() {
  return useQuery({
    queryKey: recurrencesKey,
    queryFn: () =>
      apiFetch<{ recurrences: Recurrence[] }>('/api/v1/recurrences').then((r) => r.recurrences),
  })
}

// Gasto (consolidado) já lançado desta recorrência — histórico do detalhe.
// `excluded` = removido manualmente do grupo (RF9.7), pode ser restaurado.
export type RecurrenceTransaction = {
  id: string
  title: string
  amount_cents: number
  occurred_at: string
  excluded: boolean
}

// GET /api/v1/recurrences/:id/transactions. Lazy: só busca quando o detalhe abre.
export function useRecurrenceTransactions(id: string | null) {
  return useQuery({
    queryKey: id ? (['recurrences', id, 'transactions'] as const) : (['recurrences', 'none'] as const),
    enabled: !!id,
    queryFn: () =>
      apiFetch<{ transactions: RecurrenceTransaction[] }>(`/api/v1/recurrences/${id}/transactions`)
        .then((r) => r.transactions),
  })
}

export type RecurrenceUpdate = Partial<
  Pick<
    Recurrence,
    | 'descriptor_pattern'
    | 'expected_amount_cents'
    | 'amount_tolerance_pct'
    | 'cadence'
    | 'next_expected_at'
    | 'status'
  >
>

export function useUpdateRecurrence() {
  const qc = useQueryClient()
  return useMutation({
    // PATCH usa params flat (params.permit no controller, sem wrapper).
    mutationFn: ({ id, ...patch }: { id: string } & RecurrenceUpdate) =>
      apiFetch(`/api/v1/recurrences/${id}`, { method: 'PATCH', body: patch }),
    onSuccess: () => qc.invalidateQueries({ queryKey: recurrencesKey }),
  })
}

// RF9.7 — marca um gasto como recorrente; o backend semeia a recorrência
// (descritor + palpite de cadência/valor) e agrupa os relacionados. Idempotente.
export function useCreateRecurrenceFromTransaction() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (transactionId: string) =>
      apiFetch<{ recurrence: Recurrence }>('/api/v1/recurrences', {
        method: 'POST',
        body: { transaction_id: transactionId },
      }).then((r) => r.recurrence),
    // Também invalida as listas de transações: o serializer marca o gasto como
    // pertencente à recorrência (RF9.7) e o detalhe precisa refletir na hora.
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: recurrencesKey })
      qc.invalidateQueries({ queryKey: ['transactions'] })
    },
  })
}

// RF9.7 — remove um gasto do grupo da recorrência (exclusão persistente).
export function useExcludeTransaction(recurrenceId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (transactionId: string) =>
      apiFetch(`/api/v1/recurrences/${recurrenceId}/exclusions`, {
        method: 'POST',
        body: { transaction_id: transactionId },
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['recurrences', recurrenceId, 'transactions'] })
      qc.invalidateQueries({ queryKey: recurrencesKey })
      qc.invalidateQueries({ queryKey: ['transactions'] })
    },
  })
}

// RF9.7 — restaura um gasto removido de volta ao grupo.
export function useIncludeTransaction(recurrenceId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (transactionId: string) =>
      apiFetch(`/api/v1/recurrences/${recurrenceId}/exclusions/${transactionId}`, {
        method: 'DELETE',
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['recurrences', recurrenceId, 'transactions'] })
      qc.invalidateQueries({ queryKey: recurrencesKey })
      qc.invalidateQueries({ queryKey: ['transactions'] })
    },
  })
}

export const CADENCE_LABELS: Record<Cadence, string> = {
  weekly: 'Semanal',
  monthly: 'Mensal',
  yearly: 'Anual',
  custom: 'Personalizada',
}
