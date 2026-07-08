import { X, Pencil, Trash2, Tag as TagIcon, Folder, Layers } from 'lucide-react'
import { Sheet } from '../components/Sheet'
import { Button } from '../components/Button'
import { Money } from '../components/Money'
import { useBudget, useDeleteBudget, type BudgetKind } from './useBudgets'
import { BudgetProgressBar } from './BudgetProgressBar'

const KIND_ICON = { tag: TagIcon, category: Folder, composite: Layers } as const
const MONTHS_PT = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

function monthLabel(ym: string): string {
  const [, m] = ym.split('-').map(Number)
  return MONTHS_PT[m - 1] ?? ym
}
function dayMonth(iso: string): string {
  const [, m, d] = iso.split('-')
  return `${d}/${m}`
}

/**
 * Detalhe de um orçamento (RF8): progresso do mês, histórico dos últimos meses e
 * as transações que compõem o gasto. Editar abre o wizard; excluir remove e fecha.
 */
export function BudgetDetailSheet({
  budgetId, open, onClose, onEdit,
}: {
  budgetId: string | null
  open: boolean
  onClose: () => void
  onEdit: () => void
}) {
  return (
    <Sheet open={open} onClose={onClose} width={460}>
      {open && budgetId && <Inner key={budgetId} budgetId={budgetId} onClose={onClose} onEdit={onEdit} />}
    </Sheet>
  )
}

function Inner({ budgetId, onClose, onEdit }: { budgetId: string; onClose: () => void; onEdit: () => void }) {
  const { data, isLoading } = useBudget(budgetId)
  const del = useDeleteBudget()

  if (isLoading || !data) {
    return <div className="p-5 text-xs text-muted-foreground">Carregando…</div>
  }

  const b = data.budget
  const KindIcon = KIND_ICON[b.kind as BudgetKind]
  const target =
    b.kind === 'tag' ? b.target_tag?.name
    : b.kind === 'category' ? b.target_category?.name
    : `${b.composite_tags.length} tags`
  const p = b.progress

  const remove = () => {
    if (confirm(`Excluir o orçamento "${b.name}"?`)) del.mutate(b.id, { onSuccess: onClose })
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-5 pt-5 pb-4 border-b border-border">
        <div className="flex items-start justify-between gap-2.5">
          <div className="min-w-0">
            <div className="font-display text-lg font-semibold tracking-tight truncate">{b.name}</div>
            <div className="flex items-center gap-1 text-[11px] text-muted-foreground mt-0.5">
              <KindIcon size={11} className="shrink-0" />
              <span className="truncate">{target}</span>
            </div>
          </div>
          <button onClick={onClose} aria-label="Fechar" className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground shrink-0">
            <X size={16} />
          </button>
        </div>

        <div className="mt-3 flex items-baseline gap-2">
          <Money cents={p.spent_cents} className="text-3xl font-medium" />
          <span className="text-xs text-muted-foreground">de <Money cents={p.limit_cents} className="text-xs" /> · {p.pct}%</span>
        </div>
        <div className="mt-2">
          <BudgetProgressBar pct={p.pct} status={p.status} />
        </div>
        <p className="text-[11px] text-muted-foreground mt-1.5">
          Estimado pra fim do mês: <Money cents={p.projection_cents} className="text-[11px]" />
        </p>
      </div>

      {/* Body */}
      <div className="flex-1 overflow-y-auto px-5 py-5 flex flex-col gap-5">
        <section>
          <FieldLabel>Histórico</FieldLabel>
          <ul className="mt-2 space-y-2" data-testid="budget-history">
            {data.history.map((h) => (
              <li key={h.month} className="grid grid-cols-[36px_1fr_auto] items-center gap-2">
                <span className="text-[11px] text-muted-foreground capitalize">{monthLabel(h.month)}</span>
                <BudgetProgressBar pct={h.pct} status={h.status} />
                <span className="text-[11px] tabular-nums text-muted-foreground w-10 text-right">{h.pct}%</span>
              </li>
            ))}
          </ul>
        </section>

        <section>
          <FieldLabel>Transações do mês ({data.transactions.length})</FieldLabel>
          {data.transactions.length === 0 ? (
            <p className="text-xs text-muted-foreground mt-2" data-testid="budget-tx-empty">Nenhum gasto consolidado neste mês.</p>
          ) : (
            <ul className="mt-2 border border-border rounded-md overflow-hidden" data-testid="budget-transactions">
              {data.transactions.map((t) => (
                <li key={t.id} className="flex items-center justify-between gap-2 px-3 py-2.5 border-b border-border last:border-b-0">
                  <span className="min-w-0">
                    <span className="block text-[13px] truncate">{t.title}</span>
                    <span className="block text-[11px] text-muted-foreground tabular-nums">{dayMonth(t.occurred_at)}</span>
                  </span>
                  <Money cents={t.amount_cents} className="text-[13px] shrink-0" />
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>

      {/* Footer */}
      <div className="px-5 py-4 border-t border-border flex gap-2">
        <button
          onClick={remove}
          disabled={del.isPending}
          className="inline-flex items-center gap-1.5 px-3 text-sm text-destructive hover:underline disabled:opacity-50"
          data-testid="budget-detail-delete"
        >
          <Trash2 size={14} /> Excluir
        </button>
        <Button variant="primary" className="flex-1" onClick={onEdit} data-testid="budget-detail-edit">
          <Pencil size={14} /> Editar
        </Button>
      </div>
    </div>
  )
}

function FieldLabel({ children }: { children: React.ReactNode }) {
  return <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground">{children}</div>
}
