import { Plus, Tag as TagIcon, Layers, Folder, TriangleAlert } from 'lucide-react'
import { Button } from '../components/Button'
import { Money } from '../components/Money'
import { useOverlay } from '../app/useOverlay'
import { useBudgets, type Budget } from './useBudgets'
import { BudgetProgressBar } from './BudgetProgressBar'
import { BudgetWizard } from './BudgetWizard'

/**
 * Orçamentos (RF8) — lista de tetos mensais com barra de progresso. Cada card
 * mostra alvo (tag/categoria/composto), gasto vs teto, % e projeção pro fim do
 * mês. Clicar edita; o botão "Novo orçamento" abre o wizard. Overlay via ?budget.
 */
export function BudgetsPage() {
  const { data, isLoading } = useBudgets()
  const { get, push, close } = useOverlay()
  const active = get('budget') // 'new' | <id> | null

  const budgets = data?.budgets ?? []

  return (
    <div className="max-w-4xl mx-auto">
      <div className="flex items-end justify-between mb-5">
        <div>
          <h1 className="font-sans text-2xl font-semibold tracking-tight">Orçamentos</h1>
          <p className="text-xs text-muted-foreground mt-0.5">Tetos mensais por tag, categoria ou combinação</p>
        </div>
        <Button size="sm" onClick={() => push((p) => p.set('budget', 'new'))} data-testid="budget-new">
          <Plus size={14} /> Novo orçamento
        </Button>
      </div>

      {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}

      {!isLoading && budgets.length === 0 && (
        <div className="border border-border rounded-lg px-6 py-12 text-center" data-testid="budgets-empty">
          <p className="text-sm text-foreground">Você ainda não tem orçamentos</p>
          <p className="text-xs text-muted-foreground mt-1 mb-4">
            Defina um teto mensal e acompanhe o quanto já gastou.
          </p>
          <Button size="sm" onClick={() => push((p) => p.set('budget', 'new'))}>
            <Plus size={14} /> Criar o primeiro
          </Button>
        </div>
      )}

      {budgets.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {budgets.map((b) => (
            <BudgetCard key={b.id} budget={b} onClick={() => push((p) => p.set('budget', b.id))} />
          ))}
        </div>
      )}

      <BudgetWizard
        open={active != null}
        budgetId={active && active !== 'new' ? active : null}
        budgets={budgets}
        onClose={() => close('budget')}
      />
    </div>
  )
}

const KIND_ICON = { tag: TagIcon, category: Folder, composite: Layers } as const

function BudgetCard({ budget: b, onClick }: { budget: Budget; onClick: () => void }) {
  const KindIcon = KIND_ICON[b.kind]
  const target =
    b.kind === 'tag' ? b.target_tag?.name
    : b.kind === 'category' ? b.target_category?.name
    : `${b.composite_tags.length} tags`
  const { progress: p } = b

  return (
    <button
      type="button"
      onClick={onClick}
      data-testid={`budget-card-${b.id}`}
      className={`text-left border border-border rounded-lg p-4 hover:bg-muted transition-colors ${
        b.enabled ? '' : 'opacity-60'
      }`}
    >
      <div className="flex items-start justify-between gap-2 mb-3">
        <div className="min-w-0">
          <div className="text-sm font-medium truncate">{b.name}</div>
          <div className="flex items-center gap-1 text-[11px] text-muted-foreground mt-0.5">
            <KindIcon size={11} className="shrink-0" />
            <span className="truncate">{target}</span>
            {b.overlap && (
              <span className="inline-flex items-center gap-0.5 text-warning" data-testid={`budget-overlap-${b.id}`}>
                <TriangleAlert size={11} /> compartilha tag
              </span>
            )}
          </div>
        </div>
        <span
          className={`text-sm font-semibold tabular-nums shrink-0 ${
            p.status === 'exceeded' ? 'text-destructive' : p.status === 'warning' ? 'text-warning' : 'text-muted-foreground'
          }`}
          data-testid={`budget-pct-${b.id}`}
        >
          {p.pct}%
        </span>
      </div>

      <BudgetProgressBar pct={p.pct} status={p.status} />

      <div className="flex items-baseline justify-between mt-2 text-[13px]">
        <span>
          <Money cents={p.spent_cents} className="font-medium" />
          <span className="text-muted-foreground"> de </span>
          <Money cents={p.limit_cents} className="text-muted-foreground" />
        </span>
      </div>
      <p className="text-[11px] text-muted-foreground mt-1">
        Estimado pra fim do mês: <Money cents={p.projection_cents} className="text-[11px]" />
      </p>
    </button>
  )
}
