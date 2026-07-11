import { useMemo } from 'react'
import { useSearchParams } from 'react-router'
import { currentPeriod, monthRange, periodLabel, shortDateLabel } from './period'
import type { ReportFiltersState, ReportRange } from './useReports'

export type PeriodMode = 'month' | 'custom'

export interface ReportParams {
  mode: PeriodMode
  period: string // "YYYY-MM" — relevante no modo mês
  range: ReportRange // from/to sempre resolvidos (mês → 1º ao último dia)
  filters: ReportFiltersState
  search: string // querystring atual, pra herdar ao navegar pro detalhe
  setMonth: (period: string) => void
  setCustom: (from: string, to: string) => void
  setFilters: (patch: Partial<ReportFiltersState>) => void
  clearFilters: () => void
}

/**
 * Período (mês OU range custom) + filtros de relatório como estado de URL —
 * shareável, e o back do navegador volta ao estado anterior. Chaves:
 * ?period=YYYY-MM | ?from=&to= (custom), ?account_ids=a,b, ?card_only=1,
 * ?membership_id=, ?direction=debit|credit.
 */
export function useReportParams(): ReportParams {
  const [sp, setSp] = useSearchParams()

  const from = sp.get('from')
  const to = sp.get('to')
  const custom = !!(from && to)
  const period = sp.get('period') || currentPeriod()

  const range: ReportRange = custom ? { from: from!, to: to! } : monthRange(period)

  const filters: ReportFiltersState = useMemo(() => {
    const accountIds = sp.get('account_ids')
    const direction = sp.get('direction')
    return {
      accountIds: accountIds ? accountIds.split(',').filter(Boolean) : [],
      cardOnly: sp.get('card_only') === '1',
      membershipId: sp.get('membership_id') || null,
      direction: direction === 'credit' ? 'credit' : direction === 'debit' ? 'debit' : undefined,
    }
  }, [sp])

  const patchParams = (mutate: (next: URLSearchParams) => void) => {
    setSp(
      (prev) => {
        const next = new URLSearchParams(prev)
        mutate(next)
        return next
      },
      { replace: true },
    )
  }

  const setMonth = (p: string) =>
    patchParams((next) => {
      next.delete('from')
      next.delete('to')
      next.set('period', p)
    })

  const setCustom = (f: string, t: string) =>
    patchParams((next) => {
      next.delete('period')
      next.set('from', f)
      next.set('to', t)
    })

  const setFilters = (patch: Partial<ReportFiltersState>) =>
    patchParams((next) => {
      if ('accountIds' in patch) {
        const ids = patch.accountIds ?? []
        if (ids.length) next.set('account_ids', ids.join(','))
        else next.delete('account_ids')
      }
      if ('cardOnly' in patch) {
        if (patch.cardOnly) next.set('card_only', '1')
        else next.delete('card_only')
      }
      if ('membershipId' in patch) {
        if (patch.membershipId) next.set('membership_id', patch.membershipId)
        else next.delete('membership_id')
      }
      if ('direction' in patch) {
        if (patch.direction) next.set('direction', patch.direction)
        else next.delete('direction')
      }
    })

  const clearFilters = () =>
    patchParams((next) => {
      for (const k of ['account_ids', 'card_only', 'membership_id', 'direction']) next.delete(k)
    })

  return {
    mode: custom ? 'custom' : 'month',
    period,
    range,
    filters,
    search: sp.toString(),
    setMonth,
    setCustom,
    setFilters,
    clearFilters,
  }
}

// Rótulo do período ativo pra headers ("mai · 2026" ou "5 mai – 20 mai").
export function periodRangeLabel(params: ReportParams): string {
  if (params.mode === 'month') return periodLabel(params.period)
  return `${shortDateLabel(params.range.from)} – ${shortDateLabel(params.range.to)}`
}
