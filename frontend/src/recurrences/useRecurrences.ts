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

export const CADENCE_LABELS: Record<Cadence, string> = {
  weekly: 'Semanal',
  monthly: 'Mensal',
  yearly: 'Anual',
  custom: 'Personalizada',
}
