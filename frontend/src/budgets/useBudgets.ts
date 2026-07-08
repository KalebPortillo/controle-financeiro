import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

export type BudgetStatus = 'ok' | 'warning' | 'exceeded'

export type BudgetProgress = {
  spent_cents: number
  limit_cents: number
  pct: number
  status: BudgetStatus
  projection_cents: number
  remaining_cents: number
}

export type BudgetKind = 'tag' | 'category' | 'composite'
export type BudgetTargetRef = { id: string; name: string; color: string | null }

export type Budget = {
  id: string
  name: string
  kind: BudgetKind
  monthly_limit_cents: number
  alert_threshold_pct: number
  enabled: boolean
  starts_on: string | null
  ends_on: string | null
  target_tag: BudgetTargetRef | null
  target_category: BudgetTargetRef | null
  composite_tags: BudgetTargetRef[]
  // RF6.6 — sinaliza que este orçamento compartilha tag(s) com outro habilitado.
  overlap: boolean
  progress: BudgetProgress
}

export type BudgetsPayload = { period: { from: string; to: string }; budgets: Budget[] }

export type BudgetHistoryEntry = {
  month: string // 'YYYY-MM'
  spent_cents: number
  limit_cents: number
  pct: number
  status: BudgetStatus
}
export type BudgetComposingTx = { id: string; title: string; amount_cents: number; occurred_at: string }
export type BudgetDetail = { budget: Budget; history: BudgetHistoryEntry[]; transactions: BudgetComposingTx[] }

export const budgetsKey = ['budgets'] as const
export const budgetKey = (id: string) => ['budgets', id] as const

// Lista os orçamentos com o progresso do mês corrente (RF8).
export function useBudgets() {
  return useQuery({
    queryKey: budgetsKey,
    queryFn: () => apiFetch<BudgetsPayload>('/api/v1/budgets'),
  })
}

// Detalhe de um orçamento: progresso + histórico multi-mês + transações que
// compõem o gasto do mês. Lazy: só busca quando o sheet de detalhe está aberto.
export function useBudget(id: string | null) {
  return useQuery({
    queryKey: id ? budgetKey(id) : ['budgets', 'none'],
    enabled: !!id,
    queryFn: () => apiFetch<BudgetDetail>(`/api/v1/budgets/${id}`),
  })
}

export type BudgetInput = {
  name: string
  kind: BudgetKind
  monthly_limit_cents: number
  alert_threshold_pct?: number
  target_tag_id?: string | null
  target_category_id?: string | null
  composite_tag_ids?: string[]
  enabled?: boolean
}

export function useCreateBudget() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: BudgetInput) =>
      apiFetch<{ budget: Budget }>('/api/v1/budgets', { method: 'POST', body: input }),
    onSuccess: () => qc.invalidateQueries({ queryKey: budgetsKey }),
  })
}

export function useUpdateBudget() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, ...input }: BudgetInput & { id: string }) =>
      apiFetch<{ budget: Budget }>(`/api/v1/budgets/${id}`, { method: 'PATCH', body: input }),
    onSuccess: () => qc.invalidateQueries({ queryKey: budgetsKey }),
  })
}

export function useDeleteBudget() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => apiFetch(`/api/v1/budgets/${id}`, { method: 'DELETE' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: budgetsKey }),
  })
}
