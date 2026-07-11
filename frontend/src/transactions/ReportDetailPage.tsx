import { useMemo } from 'react'
import { useParams, useNavigate } from 'react-router'
import { ArrowLeft } from 'lucide-react'
import { Money } from '../components/Money'
import { useOverlay } from '../app/useOverlay'
import { TransactionDetailSheet } from './TransactionDetailSheet'
import { ConsolidatedRow } from './ConsolidatedRow'
import { ReportPeriodControl } from './ReportPeriodControl'
import { useReportParams, periodRangeLabel } from './useReportParams'
import {
  useReportsCategoryDetail,
  useReportsTagDetail,
  type DetailBreakdownItem,
  type ReportDetailData,
} from './useReports'

const PALETTE = [
  '#7C3AED', '#0EA5E9', '#F59E0B', '#EC4899', '#DC2626',
  '#14B8A6', '#16A34A', '#8B5CF6', '#F97316', '#64748B',
]

// Barras horizontais da quebra interna (tags-membro da categoria / contas da tag).
function BreakdownBars({ items }: { items: DetailBreakdownItem[] }) {
  const max = Math.max(...items.map((i) => i.amount_cents), 1)
  if (items.length === 0) return <p className="text-xs text-muted-foreground">Sem quebra disponível</p>
  return (
    <ul className="space-y-3">
      {items.map((it, i) => (
        <li key={it.id} className="grid grid-cols-[1fr_auto] gap-2 items-center text-xs">
          <div>
            <div className="flex items-center gap-1.5 mb-1">
              <span className="h-1.5 w-1.5 rounded-full" style={{ background: it.color || PALETTE[i % PALETTE.length] }} />
              <span className="text-foreground font-medium">{it.name}</span>
              <span className="text-muted-foreground">· {it.transactions_count}</span>
            </div>
            <div className="h-1.5 rounded-full bg-muted overflow-hidden">
              <div className="h-full rounded-full"
                style={{ width: `${(it.amount_cents / max) * 100}%`, background: it.color || PALETTE[i % PALETTE.length] }} />
            </div>
          </div>
          <Money cents={it.amount_cents} className="tabular-nums text-right" />
        </li>
      ))}
    </ul>
  )
}

function SummaryStrip({ data, income }: { data: ReportDetailData; income: boolean }) {
  const s = data.summary
  const hasDelta = s.delta_pct != null
  // gasto: cair é bom; receita: subir é bom.
  const good = s.delta_pct != null && (income ? s.delta_pct >= 0 : s.delta_pct <= 0)
  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
      <div className="border border-border rounded-lg p-4">
        <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground mb-1.5">Total</div>
        <Money cents={income ? s.amount_cents : -s.amount_cents} signed className="text-xl font-semibold" />
      </div>
      <div className="border border-border rounded-lg p-4">
        <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground mb-1.5">Transações</div>
        <div className="text-xl font-semibold tabular-nums">{s.transactions_count}</div>
      </div>
      <div className="border border-border rounded-lg p-4">
        <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground mb-1.5">Participação</div>
        <div className="text-xl font-semibold tabular-nums">{s.share_pct.toFixed(1).replace('.', ',')}%</div>
      </div>
      <div className="border border-border rounded-lg p-4">
        <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground mb-1.5">vs anterior</div>
        {hasDelta ? (
          <div className={`text-xl font-semibold tabular-nums ${good ? 'text-green-600' : 'text-destructive'}`}>
            {s.delta_pct! > 0 ? '+' : ''}{s.delta_pct!.toFixed(1)}%
          </div>
        ) : (
          <div className="text-xl font-semibold text-muted-foreground">—</div>
        )}
      </div>
    </div>
  )
}

/**
 * Detalhe de drill-down de uma categoria ou tag (RF13.8): resumo (total, nº,
 * participação, comparativo), quebra interna e lista de transações do período.
 * Herda período/filtros da URL (useReportParams).
 */
export function ReportDetailPage({ dimension }: { dimension: 'category' | 'tag' }) {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const params = useReportParams()
  const { range, filters } = params
  const income = (filters.direction ?? 'debit') === 'credit'

  const catQuery = useReportsCategoryDetail(dimension === 'category' ? id : '', range, filters)
  const tagQuery = useReportsTagDetail(dimension === 'tag' ? id : '', range, filters)
  const { data, isLoading, isError } = dimension === 'category' ? catQuery : tagQuery

  const { get, push, close } = useOverlay()
  const activeId = get('tx')
  const transactions = useMemo(() => data?.transactions ?? [], [data?.transactions])
  const active = transactions.find((t) => t.id === activeId) ?? null

  const breakdownTitle = dimension === 'category' ? 'Por tag' : 'Por conta'

  return (
    <div className="max-w-4xl mx-auto">
      <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
        <button
          onClick={() => navigate(-1)}
          data-testid="detail-back"
          className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft size={16} /> Relatórios
        </button>
        <ReportPeriodControl params={params} />
      </div>

      {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}
      {isError && <p className="text-sm text-destructive" data-testid="detail-error">Não encontrado</p>}

      {data && (
        <>
          <div className="mb-6">
            <div className="text-xs text-muted-foreground">{periodRangeLabel(params)}</div>
            <div className="flex items-center gap-2 mt-1">
              <span className="h-3 w-3 rounded-full shrink-0" style={{ background: data.color || PALETTE[0] }} />
              <h1 className="font-sans text-2xl font-semibold tracking-tight">{data.name}</h1>
            </div>
          </div>

          <SummaryStrip data={data} income={income} />

          <div className="border border-border rounded-lg p-4 mb-4">
            <div className="text-sm font-semibold mb-4">{breakdownTitle}</div>
            <BreakdownBars items={data.breakdown} />
          </div>

          <div className="text-sm font-semibold mb-2">Transações · {transactions.length}</div>
          {transactions.length > 0 ? (
            <div className="border border-border rounded-lg overflow-hidden">
              {transactions.map((t) => (
                <ConsolidatedRow key={t.id} t={t} onOpen={() => push((p) => p.set('tx', t.id))} />
              ))}
            </div>
          ) : (
            <p className="text-sm text-muted-foreground" data-testid="detail-empty">Nenhuma transação no período</p>
          )}
        </>
      )}

      <TransactionDetailSheet
        transaction={active}
        open={activeId != null}
        onClose={() => close('tx')}
        mode="consolidated"
      />
    </div>
  )
}

export function CategoryDetailPage() {
  return <ReportDetailPage dimension="category" />
}

export function TagDetailPage() {
  return <ReportDetailPage dimension="tag" />
}
