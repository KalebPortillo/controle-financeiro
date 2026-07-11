import { useMemo } from 'react'
import { useNavigate } from 'react-router'
import { Info } from 'lucide-react'
import { Money } from '../components/Money'
import { ReportPeriodControl } from './ReportPeriodControl'
import { ReportFilters } from './ReportFilters'
import { useReportParams, periodRangeLabel } from './useReportParams'
import {
  useReportsOverview,
  useReportsByTag,
  useReportsByCategory,
  useMonthlyEvolution,
  type CategoryBreakdown,
  type TagBreakdown,
  type MonthEntry,
} from './useReports'

// Palette de fallback para categorias/tags sem cor definida
const PALETTE = [
  '#7C3AED', '#0EA5E9', '#F59E0B', '#EC4899', '#DC2626',
  '#14B8A6', '#16A34A', '#8B5CF6', '#F97316', '#64748B',
]

function colorFor(item: { color: string | null }, idx: number): string {
  return item.color || PALETTE[idx % PALETTE.length]
}

// ---------------------------------------------------------------------------
// KPI card
// ---------------------------------------------------------------------------
function KpiCard({
  label, cents, signed, deltaPct,
}: {
  label: string
  cents: number
  signed?: boolean
  deltaPct?: number | null
}) {
  const hasDelta = deltaPct != null
  const positive = deltaPct != null && deltaPct <= 0 // menor gasto = bom
  return (
    <div className="border border-border rounded-lg p-4">
      <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground mb-1.5">{label}</div>
      <Money cents={cents} signed={signed} className="text-2xl font-semibold" />
      {hasDelta && (
        <div className={`text-[11px] mt-1 ${positive ? 'text-green-600' : 'text-destructive'}`}>
          {deltaPct! > 0 ? '+' : ''}{deltaPct!.toFixed(1)}% vs período anterior
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Donut SVG (categorias) — fatias e legenda navegam pro detalhe da categoria
// ---------------------------------------------------------------------------
function Donut({ data, onSelect }: { data: CategoryBreakdown[]; onSelect: (id: string) => void }) {
  const total = data.reduce((s, d) => s + d.amount_cents, 0)
  const size  = 200
  const cx    = size / 2
  const cy    = size / 2
  const r     = size / 2 - 6
  const inner = r * 0.66

  const arcs = useMemo(() => {
    return data.map((d, i) => {
      const startCents = data.slice(0, i).reduce((s, x) => s + x.amount_cents, 0)
      const endCents   = startCents + d.amount_cents
      const a0 = (startCents / total) * 2 * Math.PI - Math.PI / 2
      const a1 = (endCents   / total) * 2 * Math.PI - Math.PI / 2
      const large = d.amount_cents > total / 2 ? 1 : 0
      const x0 = cx + r * Math.cos(a0), y0 = cy + r * Math.sin(a0)
      const x1 = cx + r * Math.cos(a1), y1 = cy + r * Math.sin(a1)
      const xi0 = cx + inner * Math.cos(a0), yi0 = cy + inner * Math.sin(a0)
      const xi1 = cx + inner * Math.cos(a1), yi1 = cy + inner * Math.sin(a1)
      const path = `M ${x0} ${y0} A ${r} ${r} 0 ${large} 1 ${x1} ${y1} L ${xi1} ${yi1} A ${inner} ${inner} 0 ${large} 0 ${xi0} ${yi0} Z`
      return { path, color: colorFor(d, i), d }
    })
  }, [data, total, cx, cy, r, inner])

  const compact = (n: number) =>
    n >= 100000
      ? `R$ ${(n / 100000).toFixed(1).replace('.', ',')}k`
      : `R$ ${(n / 100).toFixed(0)}`

  return (
    <div className="flex flex-col sm:flex-row items-start gap-4">
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="shrink-0">
        {arcs.map(({ path, color, d }) => (
          <path
            key={d.category_id}
            d={path}
            fill={color}
            role="button"
            tabIndex={0}
            aria-label={`Ver detalhes de ${d.name}`}
            className="cursor-pointer outline-none hover:opacity-80"
            onClick={() => onSelect(d.category_id)}
          />
        ))}
        <text x={cx} y={cy - 8} textAnchor="middle" dominantBaseline="middle"
          style={{ font: '500 10px var(--font-sans)', fill: 'var(--muted-foreground)', textTransform: 'uppercase', letterSpacing: '0.06em' }}>
          total
        </text>
        <text x={cx} y={cy + 10} textAnchor="middle" dominantBaseline="middle"
          style={{ font: '500 18px var(--font-sans)', fill: 'var(--foreground)' }}>
          {compact(total)}
        </text>
      </svg>
      <ul className="flex-1 space-y-1 text-xs min-w-0 w-full">
        {arcs.map(({ color, d }) => (
          <li key={d.category_id}>
            <button
              onClick={() => onSelect(d.category_id)}
              data-testid={`donut-cat-${d.category_id}`}
              aria-label={`Ver detalhes de ${d.name}`}
              className="flex items-center gap-2 min-w-0 w-full text-left rounded-md px-1.5 py-1 hover:bg-muted"
            >
              <span className="h-2 w-2 rounded-full shrink-0" style={{ background: color }} />
              <span className="truncate flex-1 text-foreground">{d.name}</span>
              <Money cents={d.amount_cents} className="font-medium tabular-nums shrink-0" />
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Horizontal bar list (top tags) — cada linha navega pro detalhe da tag
// ---------------------------------------------------------------------------
function HBar({ data, onSelect }: { data: TagBreakdown[]; onSelect: (id: string) => void }) {
  const max = Math.max(...data.map((t) => t.amount_cents), 1)
  return (
    <ul className="space-y-1">
      {data.map((t, i) => (
        <li key={t.tag_id}>
          <button
            onClick={() => onSelect(t.tag_id)}
            data-testid={`hbar-tag-${t.tag_id}`}
            aria-label={`Ver detalhes de ${t.name}`}
            className="grid w-full grid-cols-[1fr_auto] gap-2 items-center text-xs text-left rounded-md px-1.5 py-1.5 hover:bg-muted"
          >
            <div>
              <div className="flex items-center gap-1.5 mb-1">
                <span className="h-1.5 w-1.5 rounded-full" style={{ background: colorFor(t, i) }} />
                <span className="text-foreground font-medium">{t.name}</span>
              </div>
              <div className="h-1.5 rounded-full bg-muted overflow-hidden">
                <div
                  className="h-full rounded-full"
                  style={{ width: `${(t.amount_cents / max) * 100}%`, background: colorFor(t, i) }}
                />
              </div>
            </div>
            <Money cents={t.amount_cents} className="tabular-nums text-right" />
          </button>
        </li>
      ))}
    </ul>
  )
}

// ---------------------------------------------------------------------------
// Line chart (evolução mensal)
// ---------------------------------------------------------------------------
function LineChart({ data }: { data: MonthEntry[] }) {
  const w = 560, h = 160, pad = 28
  const values  = data.map((m) => m.expense_cents)
  const max     = Math.max(...values, 1) * 1.1
  const points  = values.map((v, i) => {
    const x = pad + (i / Math.max(values.length - 1, 1)) * (w - pad * 2)
    const y = h - pad - (v / max) * (h - pad * 2)
    return [x, y]
  })
  const pathD = points.map((p, i) => (i === 0 ? `M ${p[0]} ${p[1]}` : `L ${p[0]} ${p[1]}`)).join(' ')
  const areaD = pathD + ` L ${points[points.length - 1][0]} ${h - pad} L ${points[0][0]} ${h - pad} Z`

  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" style={{ display: 'block' }}>
      {[0.25, 0.5, 0.75].map((t) => (
        <line key={t} x1={pad} x2={w - pad}
          y1={pad + t * (h - pad * 2)} y2={pad + t * (h - pad * 2)}
          stroke="var(--border)" strokeDasharray="2 4" />
      ))}
      <path d={areaD} fill="var(--accent)" opacity="0.08" />
      <path d={pathD} fill="none" stroke="var(--accent)" strokeWidth="1.75" />
      {points.map((p, i) => (
        <circle key={i} cx={p[0]} cy={p[1]} r="2.5"
          fill="var(--background)" stroke="var(--accent)" strokeWidth="1.5" />
      ))}
      {data.map((m, i) => (
        <text key={m.period}
          x={pad + (i / Math.max(data.length - 1, 1)) * (w - pad * 2)}
          y={h - 8}
          textAnchor="middle"
          style={{ font: '500 10px var(--font-sans)', fill: 'var(--muted-foreground)' }}>
          {m.period.slice(5)}
        </text>
      ))}
    </svg>
  )
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------
export function ReportsPage() {
  const navigate = useNavigate()
  const params = useReportParams()
  const { range, filters, search } = params

  const { data: overview, isLoading: loadingOverview } = useReportsOverview(range, filters)
  const { data: byTag,    isLoading: loadingTag       } = useReportsByTag(range, filters)
  const { data: byCat,    isLoading: loadingCat       } = useReportsByCategory(range, filters)
  const { data: evolution                             } = useMonthlyEvolution(12, filters)

  const label = periodRangeLabel(params)
  const income = (filters.direction ?? 'debit') === 'credit'
  const goCategory = (id: string) => navigate(`/relatorios/categoria/${id}${search ? `?${search}` : ''}`)
  const goTag = (id: string) => navigate(`/relatorios/tag/${id}${search ? `?${search}` : ''}`)

  return (
    <div className="max-w-4xl mx-auto">
      <div className="flex flex-wrap items-end justify-between gap-3 mb-4">
        <div>
          <div className="text-xs text-muted-foreground">{label} · todas as contas</div>
          <h1 className="font-sans text-2xl font-semibold tracking-tight mt-1">Relatórios</h1>
        </div>
        <ReportPeriodControl params={params} />
      </div>

      <div className="mb-6">
        <ReportFilters params={params} />
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
        {loadingOverview ? (
          <div className="col-span-3 text-xs text-muted-foreground">Carregando…</div>
        ) : overview ? (
          <>
            <KpiCard label="Total gasto"    cents={-overview.expense_cents}
              deltaPct={overview.previous_period_comparison.expense_delta_pct} />
            <KpiCard label="Total recebido" cents={overview.income_cents} signed
              deltaPct={overview.previous_period_comparison.income_delta_pct} />
            <KpiCard label="Saldo do período" cents={overview.balance_cents} signed />
          </>
        ) : null}
      </div>

      <div className="grid sm:grid-cols-2 gap-4 mb-4">
        {/* Donut — categorias */}
        <div className="border border-border rounded-lg p-4">
          <div className="flex items-start justify-between mb-4">
            <div>
              <div className="text-sm font-semibold">{income ? 'Receitas' : 'Gastos'} por categoria</div>
              <div className="text-[11px] text-muted-foreground mt-0.5">{label} · toque para detalhar</div>
            </div>
          </div>
          {loadingCat ? (
            <p className="text-xs text-muted-foreground">Carregando…</p>
          ) : byCat && byCat.categories.length > 0 ? (
            <>
              <Donut data={byCat.categories} onSelect={goCategory} />
              {byCat.overlap_present && (
                <div className="flex items-start gap-1.5 mt-4 p-2.5 rounded-md bg-muted border border-border text-[11px] text-muted-foreground">
                  <Info size={12} className="shrink-0 mt-0.5" />
                  <span>Alguns gastos aparecem em mais de uma categoria; a soma pode ser maior que o total real</span>
                </div>
              )}
            </>
          ) : (
            <p className="text-xs text-muted-foreground">Nenhuma categoria com {income ? 'receitas' : 'gastos'} neste período</p>
          )}
        </div>

        {/* HBar — top tags */}
        <div className="border border-border rounded-lg p-4">
          <div className="mb-4">
            <div className="text-sm font-semibold">Top tags do período</div>
            <div className="text-[11px] text-muted-foreground mt-0.5">por valor · toque para detalhar</div>
          </div>
          {loadingTag ? (
            <p className="text-xs text-muted-foreground">Carregando…</p>
          ) : byTag && byTag.tags.length > 0 ? (
            <HBar data={byTag.tags.slice(0, 6)} onSelect={goTag} />
          ) : (
            <p className="text-xs text-muted-foreground">Nenhuma tag com gastos neste período</p>
          )}
        </div>
      </div>

      {/* Line chart — evolução */}
      <div className="border border-border rounded-lg p-4">
        <div className="mb-4">
          <div className="text-sm font-semibold">Evolução mensal · últimos 12 meses</div>
          <div className="text-[11px] text-muted-foreground mt-0.5">total gasto</div>
        </div>
        {evolution && evolution.months.length > 0 ? (
          <LineChart data={evolution.months} />
        ) : (
          <p className="text-xs text-muted-foreground">Sem histórico disponível</p>
        )}
      </div>
    </div>
  )
}
