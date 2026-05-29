import { useQuery } from '@tanstack/react-query'

export interface ReportPeriod {
  from: string
  to: string
}

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

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json() as Promise<T>
}

export function useReportsOverview(period = 'current_month') {
  return useQuery<OverviewData>({
    queryKey: ['reports', 'overview', period],
    queryFn: () => fetchJson(`/api/v1/reports/overview?period=${period}`),
  })
}

export function useReportsByTag(from: string, to: string) {
  return useQuery<ByTagData>({
    queryKey: ['reports', 'by_tag', from, to],
    queryFn: () => fetchJson(`/api/v1/reports/by_tag?from=${from}&to=${to}`),
  })
}

export function useReportsByCategory(from: string, to: string) {
  return useQuery<ByCategoryData>({
    queryKey: ['reports', 'by_category', from, to],
    queryFn: () => fetchJson(`/api/v1/reports/by_category?from=${from}&to=${to}`),
  })
}

export function useMonthlyEvolution(months = 12) {
  return useQuery<MonthlyEvolutionData>({
    queryKey: ['reports', 'monthly_evolution', months],
    queryFn: () => fetchJson(`/api/v1/reports/monthly_evolution?months=${months}`),
  })
}
