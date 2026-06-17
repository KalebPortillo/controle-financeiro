import { useMutation, useQuery, useQueryClient, type QueryClient } from '@tanstack/react-query'
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
  // RF2.7 — fonte do gasto: tipo da conta (cartão/conta), banco e (cartão) bandeira/dígitos.
  account_kind: 'checking' | 'credit_card' | null
  institution_label: string | null
  account_institution_name: string | null
  account_brand: string | null
  account_last_digits: string | null
  // Dígitos do cartão DESTA compra (cartões virtuais Nubank têm dígitos distintos).
  card_last_digits: string | null
  // RF9.4 — parcelamento: número/total/grupo (null quando não é parcela).
  installment_number: number | null
  installment_total: number | null
  installment_group_id: string | null
  // RF9.4 — data da COMPRA (mesma pra todas as parcelas); null fora de cartão.
  purchase_date: string | null
  direction: 'debit' | 'credit'
  amount_cents: number
  currency: string
  occurred_at: string
  original_description: string
  improved_title: string | null
  ai_confidence: AiConfidence
  ai_suggestion: AiSuggestion
  // Estado da análise IA: queued (aguardando), analyzed (rodou), failed (não analisado)
  ai_status: 'queued' | 'analyzed' | 'failed'
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

// Descrição bruta do banco que vale a pena mostrar abaixo do título: só quando o
// título melhorado existe e difere do original, e o original não é o placeholder.
// (O original nunca se perde — fica sempre em original_description.)
export function originalToShow(t: Pick<InboxTransaction, 'improved_title' | 'original_description'>): string | null {
  const orig = t.original_description?.trim()
  if (!orig || orig === '(sem descrição)') return null
  if (!t.improved_title || t.improved_title.trim() === orig) return null
  return orig
}

// Chaves de cache. inbox = pendentes; consolidados são por mês (lazy).
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

// ── Cache cirúrgico ─────────────────────────────────────────────────────────
// Em vez de invalidar ['transactions'] (que recarregava a inbox INTEIRA a cada
// ação — caro com lista grande), atualizamos só o item afetado no cache. A API
// já devolve o registro atualizado, então não há refetch da lista.
const consolidatedBranch = ['transactions', 'consolidated'] as const

function patchInbox(qc: QueryClient, fn: (p: InboxPayload) => InboxPayload) {
  qc.setQueryData<InboxPayload>(inboxKey, (old) => (old ? fn(old) : old))
}

// Remove transações da lista pendente e ajusta o contador.
export function dropFromInbox(qc: QueryClient, ids: Iterable<string>) {
  const drop = new Set(ids)
  if (drop.size === 0) return
  patchInbox(qc, (p) => {
    const transactions = p.transactions.filter((t) => !drop.has(t.id))
    const removed = p.transactions.length - transactions.length
    return { transactions, pending_count: Math.max(0, p.pending_count - removed) }
  })
}

// Substitui uma transação na lista pelo registro atualizado (ex.: nova tag).
function replaceInInbox(qc: QueryClient, tx: InboxTransaction) {
  patchInbox(qc, (p) => ({
    ...p,
    transactions: p.transactions.map((t) => (t.id === tx.id ? tx : t)),
  }))
}

// Ids das parcelas pendentes de um parcelamento, lidos do cache.
function parcelIds(qc: QueryClient, groupId: string): string[] {
  const inbox = qc.getQueryData<InboxPayload>(inboxKey)
  return inbox?.transactions.filter((t) => t.installment_group_id === groupId).map((t) => t.id) ?? []
}

type InboxSnapshot = { prev?: InboxPayload }

// Mutation que REMOVE itens da inbox (aceitar/rejeitar/remover): otimista —
// some da lista na hora, com rollback se a request falhar. `idsOf` extrai os
// ids afetados do input (lendo o cache quando preciso, ex.: parcelamento).
function useInboxRemoval<TInput>(
  fn: (input: TInput) => Promise<unknown>,
  idsOf: (input: TInput, qc: QueryClient) => string[],
  { movesToConsolidated = false } = {},
) {
  const qc = useQueryClient()
  return useMutation<unknown, Error, TInput, InboxSnapshot>({
    mutationFn: fn,
    onMutate: async (input) => {
      await qc.cancelQueries({ queryKey: inboxKey })
      const prev = qc.getQueryData<InboxPayload>(inboxKey)
      dropFromInbox(qc, idsOf(input, qc))
      return { prev }
    },
    onError: (_e, _input, ctx) => {
      if (ctx?.prev) qc.setQueryData(inboxKey, ctx.prev)
    },
    onSettled: () => {
      // Consolidados (lazy, por mês) podem ter mudado; invalida só esse ramo.
      if (movesToConsolidated) qc.invalidateQueries({ queryKey: consolidatedBranch })
    },
  })
}

// Aceitar (RF2.3).
export function useConsolidate() {
  return useInboxRemoval(
    (id: string) => apiFetch(`/api/v1/transactions/${id}/consolidate`, { method: 'POST' }),
    (id) => [id],
    { movesToConsolidated: true },
  )
}

// Aceitar várias de uma vez (RF2.3) — um único request (bulk).
export function useBulkConsolidate() {
  return useInboxRemoval(
    (ids: string[]) => apiFetch('/api/v1/transactions/bulk_consolidate', { method: 'POST', body: { ids } }),
    (ids) => ids,
    { movesToConsolidated: true },
  )
}

// Rejeitar (RF2.3).
export function useReject() {
  return useInboxRemoval(
    (id: string) => apiFetch(`/api/v1/transactions/${id}/reject`, { method: 'POST' }),
    (id) => [id],
  )
}

// Rejeitar várias de uma vez (RF2.3).
export function useBulkReject() {
  return useInboxRemoval(
    (ids: string[]) => apiFetch('/api/v1/transactions/bulk_reject', { method: 'POST', body: { ids } }),
    (ids) => ids,
  )
}

// Aceitar todas as parcelas de um parcelamento de uma vez (RF9.4 — item agregado).
export function useConsolidateInstallmentGroup() {
  return useInboxRemoval(
    (groupId: string) => apiFetch(`/api/v1/installment_groups/${groupId}/consolidate`, { method: 'POST' }),
    (groupId, qc) => parcelIds(qc, groupId),
    { movesToConsolidated: true },
  )
}

// Rejeitar todas as parcelas de um parcelamento de uma vez.
export function useRejectInstallmentGroup() {
  return useInboxRemoval(
    (groupId: string) => apiFetch(`/api/v1/installment_groups/${groupId}/reject`, { method: 'POST' }),
    (groupId, qc) => parcelIds(qc, groupId),
  )
}

// Remover (RF2.3) — exclusão definitiva.
export function useRemoveTransaction() {
  return useInboxRemoval(
    (id: string) => apiFetch(`/api/v1/transactions/${id}`, { method: 'DELETE' }),
    (id) => [id],
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

// Editar título/valor/data/tags (RF2.3) com optimistic lock. A API devolve a
// transação atualizada — substituímos no cache (sem refetch da lista).
export function useUpdateTransaction() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, ...body }: UpdateInput) =>
      apiFetch<{ transaction: InboxTransaction }>(`/api/v1/transactions/${id}`, { method: 'PATCH', body }),
    onSuccess: (res) => {
      if (res?.transaction) replaceInInbox(qc, res.transaction)
      qc.invalidateQueries({ queryKey: ['transaction_edits'] }) // RF4.3: histórico reflete a edição
    },
  })
}

export type UpdateInstallmentGroupInput = {
  group_id: string
  improved_title?: string
  tag_ids?: string[]
}

// Editar título/tags de TODAS as parcelas do parcelamento (RF9.4.1). A resposta
// traz shape parcial das parcelas; como é operação rara, recarrega só a inbox.
export function useUpdateInstallmentGroup() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ group_id, ...body }: UpdateInstallmentGroupInput) =>
      apiFetch(`/api/v1/installment_groups/${group_id}`, { method: 'PATCH', body }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: inboxKey })
      qc.invalidateQueries({ queryKey: ['transaction_edits'] })
    },
  })
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
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: ManualEntryInput) =>
      apiFetch('/api/v1/transactions', { method: 'POST', body: input }),
    onSuccess: () => qc.invalidateQueries({ queryKey: consolidatedBranch }),
  })
}

// Reanalisar com IA (RF3.5) — enfileira job pra todas as transações pending.
export function useReanalyzeInbox() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => apiFetch<{ enqueued: boolean; pending_count: number }>(
      '/api/v1/transactions/reanalyze', { method: 'POST' }
    ),
    onSuccess: () => {
      // Após ~3s o job terá processado parte das sugestões; recarrega só a inbox.
      setTimeout(() => qc.invalidateQueries({ queryKey: inboxKey }), 3000)
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

// Payload cru do Pluggy (RF2.7 "exibir mais detalhes"). Lazy: só busca ao abrir.
export function useTransactionSource(id: string, enabled: boolean) {
  return useQuery({
    queryKey: ['transaction_source', id],
    enabled,
    queryFn: () =>
      apiFetch<{ source: string; source_metadata: unknown }>(`/api/v1/transactions/${id}/source`),
  })
}
