import { useQuery } from '@tanstack/react-query'
import type { InboxTransaction } from './useInbox'

export interface ReportPeriod {
  from: string
  to: string
}

// Filtros comuns aos relatórios (RF13.4). Todos opcionais.
export interface ReportFiltersState {
  accountIds?: string[]
  cardOnly?: boolean
  membershipId?: string | null
  direction?: 'debit' | 'credit'
}

// Período: mês (YYYY-MM) OU range custom (from/to). O front converte mês → from/to.
export type ReportRange = { from: string; to: string }

export interface TopTag {
  tag_id: string
  name: string
  color: string | null
  amount_cents: number
}

export interface TopCategory {
  category_id: string
  name: string
  color: string | null
  amount_cents: number
}

export interface OverviewData {
  period: ReportPeriod
  expense_cents: number
  income_cents: number
  balance_cents: number
  top_tags: TopTag[]
  top_categories: TopCategory[]
  previous_period_comparison: {
    expense_delta_pct: number | null
    income_delta_pct: number | null
  }
}

export interface TagBreakdown {
  tag_id: string
  name: string
  color: string | null
  amount_cents: number
  transactions_count: number
}

export interface CategoryBreakdown {
  category_id: string
  name: string
  color: string | null
  amount_cents: number
  transactions_count: number
  shared_with_other_categories_count: number
}

export interface ByTagData {
  tags: TagBreakdown[]
}

export interface ByCategoryData {
  categories: CategoryBreakdown[]
  total_distinct_transactions_amount_cents: number
  sum_of_categories_amount_cents: number
  overlap_present: boolean
}

export interface MonthEntry {
  period: string
  expense_cents: number
  income_cents: number
}

export interface MonthlyEvolutionData {
  months: MonthEntry[]
}

// RF13.8 — detalhe de drill-down (categoria ou tag).
export interface DetailBreakdownItem {
  id: string
  name: string
  color: string | null
  amount_cents: number
  transactions_count: number
}

export interface ReportDetailData {
  id: string
  name: string
  color: string | null
  period: ReportPeriod
  summary: {
    amount_cents: number
    transactions_count: number
    share_pct: number
    previous_amount_cents: number
    delta_pct: number | null
  }
  breakdown: DetailBreakdownItem[]
  transactions: InboxTransaction[]
}

// Monta a query string a partir de range + filtros. Chaves estáveis pra cache.
function buildQuery(range: ReportRange, filters: ReportFiltersState = {}): string {
  const p = new URLSearchParams()
  p.set('from', range.from)
  p.set('to', range.to)
  for (const id of filters.accountIds ?? []) p.append('account_ids[]', id)
  if (filters.cardOnly) p.set('card_only', 'true')
  if (filters.membershipId) p.set('membership_id', filters.membershipId)
  if (filters.direction) p.set('direction', filters.direction)
  return p.toString()
}

// Chave de cache determinística pros filtros (ordena as contas).
function filtersKey(filters: ReportFiltersState = {}): string {
  return JSON.stringify({
    a: [...(filters.accountIds ?? [])].sort(),
    c: filters.cardOnly ?? false,
    m: filters.membershipId ?? null,
    d: filters.direction ?? null,
  })
}

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json() as Promise<T>
}

export function useReportsOverview(range: ReportRange, filters: ReportFiltersState = {}) {
  const qs = buildQuery(range, filters)
  return useQuery<OverviewData>({
    queryKey: ['reports', 'overview', range.from, range.to, filtersKey(filters)],
    queryFn: () => fetchJson(`/api/v1/reports/overview?${qs}`),
  })
}

export function useReportsByTag(range: ReportRange, filters: ReportFiltersState = {}) {
  const qs = buildQuery(range, filters)
  return useQuery<ByTagData>({
    queryKey: ['reports', 'by_tag', range.from, range.to, filtersKey(filters)],
    queryFn: () => fetchJson(`/api/v1/reports/by_tag?${qs}`),
  })
}

export function useReportsByCategory(range: ReportRange, filters: ReportFiltersState = {}) {
  const qs = buildQuery(range, filters)
  return useQuery<ByCategoryData>({
    queryKey: ['reports', 'by_category', range.from, range.to, filtersKey(filters)],
    queryFn: () => fetchJson(`/api/v1/reports/by_category?${qs}`),
  })
}

export function useMonthlyEvolution(months = 12, filters: ReportFiltersState = {}) {
  const p = new URLSearchParams({ months: String(months) })
  for (const id of filters.accountIds ?? []) p.append('account_ids[]', id)
  if (filters.cardOnly) p.set('card_only', 'true')
  if (filters.membershipId) p.set('membership_id', filters.membershipId)
  return useQuery<MonthlyEvolutionData>({
    queryKey: ['reports', 'monthly_evolution', months, filtersKey(filters)],
    queryFn: () => fetchJson(`/api/v1/reports/monthly_evolution?${p.toString()}`),
  })
}

export function useReportsCategoryDetail(id: string, range: ReportRange, filters: ReportFiltersState = {}) {
  const qs = buildQuery(range, filters)
  return useQuery<ReportDetailData>({
    queryKey: ['reports', 'category_detail', id, range.from, range.to, filtersKey(filters)],
    queryFn: () => fetchJson(`/api/v1/reports/category/${id}?${qs}`),
    enabled: !!id,
  })
}

export function useReportsTagDetail(id: string, range: ReportRange, filters: ReportFiltersState = {}) {
  const qs = buildQuery(range, filters)
  return useQuery<ReportDetailData>({
    queryKey: ['reports', 'tag_detail', id, range.from, range.to, filtersKey(filters)],
    queryFn: () => fetchJson(`/api/v1/reports/tag/${id}?${qs}`),
    enabled: !!id,
  })
}
