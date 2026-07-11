import { useState } from 'react'
import { Filter, X } from 'lucide-react'
import { useSession } from '../auth/useSession'
import { useMemberships } from '../workspace/useMemberships'
import { useAccounts } from './useAccounts'
import type { ReportParams } from './useReportParams'

/**
 * Barra de filtros dos relatórios (RF13.4): conta/cartão, pessoa (dona da conta)
 * e direção (gasto/receita). Sóbria, chips de filtro ativo com limpar. Estado na
 * URL via useReportParams.
 */
export function ReportFilters({ params }: { params: ReportParams }) {
  const { filters, setFilters, clearFilters } = params
  const [open, setOpen] = useState(false)

  const { data: accounts } = useAccounts()
  const { data: session } = useSession()
  const { data: memberships } = useMemberships(session?.active_workspace_id)

  const accountIds = filters.accountIds ?? []
  const activeCount =
    accountIds.length +
    (filters.cardOnly ? 1 : 0) +
    (filters.membershipId ? 1 : 0) +
    (filters.direction ? 1 : 0)

  const toggleAccount = (id: string) => {
    const next = accountIds.includes(id) ? accountIds.filter((a) => a !== id) : [...accountIds, id]
    setFilters({ accountIds: next })
  }

  return (
    <div data-testid="report-filters">
      <div className="flex items-center gap-2">
        <button
          onClick={() => setOpen((v) => !v)}
          data-testid="filters-toggle"
          aria-expanded={open}
          className="inline-flex items-center gap-1.5 h-8 px-2.5 rounded-md border border-border text-xs text-foreground hover:bg-muted"
        >
          <Filter size={13} />
          Filtros
          {activeCount > 0 && (
            <span className="ml-0.5 inline-flex items-center justify-center min-w-4 h-4 px-1 rounded-full bg-accent text-accent-foreground text-[10px] font-medium tabular-nums">
              {activeCount}
            </span>
          )}
        </button>
        {activeCount > 0 && (
          <button
            onClick={clearFilters}
            data-testid="filters-clear"
            className="text-xs text-muted-foreground hover:text-foreground inline-flex items-center gap-1"
          >
            <X size={12} /> Limpar
          </button>
        )}
      </div>

      {open && (
        <div className="mt-3 border border-border rounded-lg p-4 grid gap-4 sm:grid-cols-3" data-testid="filters-panel">
          {/* Direção */}
          <div>
            <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground mb-1.5">Direção</div>
            <div className="inline-flex rounded-md border border-border overflow-hidden">
              {([
                ['debit', 'Gastos'],
                ['credit', 'Receitas'],
              ] as const).map(([value, label]) => {
                const active = (filters.direction ?? 'debit') === value
                return (
                  <button
                    key={value}
                    data-testid={`direction-${value}`}
                    onClick={() => setFilters({ direction: value === 'debit' ? undefined : 'credit' })}
                    className={`h-8 px-3 text-xs ${active ? 'bg-accent text-accent-foreground' : 'text-muted-foreground hover:bg-muted'}`}
                  >
                    {label}
                  </button>
                )
              })}
            </div>
          </div>

          {/* Pessoa */}
          <div>
            <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground mb-1.5">Pessoa</div>
            <select
              data-testid="filter-person"
              value={filters.membershipId ?? ''}
              onChange={(e) => setFilters({ membershipId: e.target.value || null })}
              className="h-8 w-full rounded-md border border-input bg-background px-2 text-sm text-foreground focus:border-ring focus:outline-2 focus:outline-ring/30"
            >
              <option value="">Todas</option>
              {(memberships ?? []).map((m) => (
                <option key={m.id} value={m.id}>
                  {m.user.name}
                </option>
              ))}
            </select>
          </div>

          {/* Só cartão */}
          <div>
            <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground mb-1.5">Tipo</div>
            <label className="inline-flex items-center gap-2 text-sm text-foreground cursor-pointer h-8">
              <input
                type="checkbox"
                data-testid="filter-card-only"
                checked={!!filters.cardOnly}
                onChange={(e) => setFilters({ cardOnly: e.target.checked })}
                className="h-4 w-4 rounded border-input accent-accent"
              />
              Só cartão de crédito
            </label>
          </div>

          {/* Contas */}
          <div className="sm:col-span-3">
            <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground mb-1.5">Contas</div>
            <div className="flex flex-wrap gap-1.5">
              {(accounts ?? []).map((a) => {
                const active = accountIds.includes(a.id)
                return (
                  <button
                    key={a.id}
                    data-testid={`filter-account-${a.id}`}
                    onClick={() => toggleAccount(a.id)}
                    className={`inline-flex items-center gap-1 h-7 px-2.5 rounded-md border text-xs ${
                      active
                        ? 'border-accent bg-accent/10 text-foreground'
                        : 'border-border text-muted-foreground hover:bg-muted'
                    }`}
                  >
                    {a.name}
                    {a.last_digits && <span className="font-mono text-[10px] text-muted-foreground">·{a.last_digits}</span>}
                  </button>
                )
              })}
              {(accounts ?? []).length === 0 && (
                <span className="text-xs text-muted-foreground">Nenhuma conta</span>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
