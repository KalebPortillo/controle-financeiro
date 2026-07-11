import { useState } from 'react'
import { CalendarRange, ChevronLeft, ChevronRight, X } from 'lucide-react'
import { shiftPeriod, periodLabel } from './period'
import type { ReportParams } from './useReportParams'

/**
 * Navegação de período dos relatórios: chevrons de mês (como em Gastos) + toggle
 * de período custom (data início/fim). Estado mora na URL via useReportParams.
 */
export function ReportPeriodControl({ params }: { params: ReportParams }) {
  const { mode, period, range, setMonth, setCustom } = params
  const [editingCustom, setEditingCustom] = useState(false)

  if (mode === 'custom' || editingCustom) {
    return (
      <div className="flex flex-wrap items-center gap-2" data-testid="period-custom">
        <div className="flex items-center gap-1.5">
          <input
            type="date"
            aria-label="Data de início"
            data-testid="custom-from"
            defaultValue={range.from}
            onChange={(e) => e.target.value && setCustom(e.target.value, range.to)}
            className="h-8 rounded-md border border-input bg-background px-2 text-sm text-foreground focus:border-ring focus:outline-2 focus:outline-ring/30"
          />
          <span className="text-muted-foreground text-xs">até</span>
          <input
            type="date"
            aria-label="Data de fim"
            data-testid="custom-to"
            defaultValue={range.to}
            onChange={(e) => e.target.value && setCustom(range.from, e.target.value)}
            className="h-8 rounded-md border border-input bg-background px-2 text-sm text-foreground focus:border-ring focus:outline-2 focus:outline-ring/30"
          />
        </div>
        <button
          onClick={() => {
            setEditingCustom(false)
            setMonth(period)
          }}
          aria-label="Voltar para navegação por mês"
          data-testid="period-custom-close"
          className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted"
        >
          <X size={15} />
        </button>
      </div>
    )
  }

  return (
    <div className="flex items-center gap-1" data-testid="period-month">
      <button
        onClick={() => setMonth(shiftPeriod(period, -1))}
        aria-label="Mês anterior"
        data-testid="prev-month"
        className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted"
      >
        <ChevronLeft size={16} />
      </button>
      <span className="text-sm font-medium w-24 text-center">{periodLabel(period)}</span>
      <button
        onClick={() => setMonth(shiftPeriod(period, 1))}
        aria-label="Próximo mês"
        data-testid="next-month"
        className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted"
      >
        <ChevronRight size={16} />
      </button>
      <button
        onClick={() => setEditingCustom(true)}
        aria-label="Período customizado"
        data-testid="period-custom-open"
        title="Período customizado"
        className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted ml-1"
      >
        <CalendarRange size={16} />
      </button>
    </div>
  )
}
