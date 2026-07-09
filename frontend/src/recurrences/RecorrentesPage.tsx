import { useState } from 'react'
import { Plus, X, RotateCcw } from 'lucide-react'
import { toast } from 'sonner'
import { Money } from '../components/Money'
import { Badge } from '../components/Badge'
import { Button } from '../components/Button'
import { Input } from '../components/Input'
import { Sheet } from '../components/Sheet'
import { ApiError } from '../api/client'
import { useDebounced } from '../app/useDebounced'
import { useConsolidated } from '../transactions/useInbox'
import { displayTitle } from '../transactions/display'
import {
  useRecurrences,
  useUpdateRecurrence,
  useRecurrenceTransactions,
  useCreateRecurrenceFromTransaction,
  useExcludeTransaction,
  useIncludeTransaction,
  CADENCE_LABELS,
  type Recurrence,
  type RecurrenceUpdate,
} from './useRecurrences'

// Período corrente YYYY-MM — base do picker quando a busca está vazia.
function currentPeriod(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

// next_expected_at vem como YYYY-MM-DD; formata sem Date pra não pegar TZ.
function formatDate(iso: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}/${m}/${y}`
}

/**
 * Recorrentes (RF9) — lista de assinaturas/contas fixas detectadas (RF9.1) ou
 * cadastradas manualmente (RF9.2), com badge auto/manual. Detalhe lateral
 * (Sheet) permite editar tolerância, pausar/retomar e cancelar (RF9).
 */
export function RecorrentesPage() {
  const { data: recurrences, isLoading } = useRecurrences()
  const [selected, setSelected] = useState<Recurrence | null>(null)
  const [picking, setPicking] = useState(false)

  // Canceladas saem da lista — viram histórico, não item ativo.
  const visible = (recurrences ?? []).filter((r) => r.status !== 'cancelled')

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <section className="flex items-start justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-sans text-2xl font-semibold tracking-tight">Recorrentes</h1>
          <p className="text-sm text-muted-foreground">
            Assinaturas e contas fixas detectadas no histórico ou cadastradas por você.
          </p>
        </div>
        <Button variant="outline" onClick={() => setPicking(true)} data-testid="new-recurrence">
          <Plus size={14} /> Nova recorrência
        </Button>
      </section>

      <div className="border border-border rounded-lg overflow-hidden">
        {isLoading && <p className="text-xs text-muted-foreground px-4 py-3">Carregando…</p>}
        {!isLoading && visible.length === 0 && (
          <p className="text-sm text-muted-foreground px-4 py-3" data-testid="recurrences-empty">
            Nenhuma recorrência ainda.
          </p>
        )}
        {visible.map((r) => (
          <RecurrenceRow key={r.id} recurrence={r} onOpen={() => setSelected(r)} />
        ))}
      </div>

      <Sheet open={selected !== null} onClose={() => setSelected(null)}>
        {selected && <RecurrenceDetail recurrence={selected} onClose={() => setSelected(null)} />}
      </Sheet>

      <Sheet open={picking} onClose={() => setPicking(false)}>
        {picking && <RecurrenceTransactionPicker onClose={() => setPicking(false)} />}
      </Sheet>
    </div>
  )
}

// RF9.7 — escolhe um gasto consolidado pra virar recorrência. Busca server-side
// (?q= em todos os períodos) reaproveitando useConsolidated; vazio mostra o mês.
function RecurrenceTransactionPicker({ onClose }: { onClose: () => void }) {
  const [q, setQ] = useState('')
  const debouncedQ = useDebounced(q, 250)
  const { data, isLoading } = useConsolidated(currentPeriod(), debouncedQ)
  const create = useCreateRecurrenceFromTransaction()

  // Só débitos (gastos) viram recorrente.
  const gastos = (data?.transactions ?? []).filter((t) => t.direction === 'debit')

  const pick = async (id: string) => {
    try {
      await create.mutateAsync(id)
      toast.success('Marcada como recorrente', {
        description: 'Gastos parecidos foram agrupados',
      })
      onClose()
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : 'Erro ao criar recorrência')
    }
  }

  return (
    <div className="space-y-4">
      <div className="space-y-1">
        <h2 className="text-lg font-semibold">Nova recorrência</h2>
        <p className="text-sm text-muted-foreground">
          Escolha um gasto — os parecidos são agrupados automaticamente.
        </p>
      </div>

      <Input
        autoFocus
        placeholder="Buscar gasto"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        data-testid="recurrence-picker-search"
      />

      {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}
      {!isLoading && gastos.length === 0 && (
        <p className="text-sm text-muted-foreground" data-testid="recurrence-picker-empty">
          Nenhum gasto encontrado.
        </p>
      )}
      {gastos.length > 0 && (
        <ul className="border border-border rounded-md overflow-hidden">
          {gastos.map((t) => (
            <li key={t.id}>
              <button
                type="button"
                onClick={() => pick(t.id)}
                disabled={create.isPending}
                data-testid={`recurrence-pick-${t.id}`}
                className="w-full flex items-center justify-between gap-2 px-3 py-2.5 border-b border-border last:border-b-0 text-left hover:bg-muted/50 disabled:opacity-50"
              >
                <span className="min-w-0">
                  <span className="block text-[13px] truncate">{displayTitle(t)}</span>
                  <span className="block text-[11px] text-muted-foreground tabular-nums">
                    {formatDate(t.occurred_at)}
                  </span>
                </span>
                <Money cents={t.amount_cents} className="text-[13px] shrink-0" />
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function SourceBadge({ source }: { source: Recurrence['source'] }) {
  return (
    <Badge variant={source === 'detected' ? 'secondary' : 'outline'}>
      {source === 'detected' ? 'auto' : 'manual'}
    </Badge>
  )
}

function RecurrenceRow({ recurrence: r, onOpen }: { recurrence: Recurrence; onOpen: () => void }) {
  return (
    <button
      onClick={onOpen}
      data-testid={`recurrence-row-${r.id}`}
      className="w-full flex items-center gap-3 px-4 py-3 border-b border-border last:border-b-0 text-left hover:bg-muted/50"
    >
      <div className="min-w-0 flex-1 space-y-0.5">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium truncate">{r.descriptor_pattern}</span>
          <SourceBadge source={r.source} />
          {r.status === 'paused' && <Badge variant="outline">pausada</Badge>}
        </div>
        <div className="text-xs text-muted-foreground">
          {CADENCE_LABELS[r.cadence]} · próx. {formatDate(r.next_expected_at)}
        </div>
      </div>
      {r.expected_amount_cents != null ? (
        <Money cents={r.expected_amount_cents} />
      ) : (
        <span className="text-sm text-muted-foreground">—</span>
      )}
    </button>
  )
}

function RecurrenceDetail({ recurrence: r, onClose }: { recurrence: Recurrence; onClose: () => void }) {
  const update = useUpdateRecurrence()
  const { data: transactions, isLoading } = useRecurrenceTransactions(r.id)
  const exclude = useExcludeTransaction(r.id)
  const include = useIncludeTransaction(r.id)
  const [tolerance, setTolerance] = useState(String(r.amount_tolerance_pct))
  const [showSettings, setShowSettings] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const included = (transactions ?? []).filter((t) => !t.excluded)
  const removed = (transactions ?? []).filter((t) => t.excluded)

  const run = async (patch: RecurrenceUpdate) => {
    setError(null)
    try {
      await update.mutateAsync({ id: r.id, ...patch })
      onClose()
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Erro ao salvar')
    }
  }

  return (
    <div className="space-y-5">
      <div className="space-y-1">
        <div className="flex items-center gap-2">
          <h2 className="text-lg font-semibold">{r.descriptor_pattern}</h2>
          <SourceBadge source={r.source} />
          {r.status === 'paused' && <Badge variant="outline">pausada</Badge>}
        </div>
        <p className="text-sm text-muted-foreground">
          {CADENCE_LABELS[r.cadence]} · próximo {formatDate(r.next_expected_at)}
          {r.expected_amount_cents != null && (
            <> · ~<Money cents={r.expected_amount_cents} className="text-sm" /></>
          )}
        </p>
      </div>

      {/* Histórico de gastos desta recorrência — conteúdo principal do detalhe. */}
      <section className="space-y-2">
        <span className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground">
          Gastos desta recorrência
        </span>
        {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}
        {!isLoading && included.length === 0 && (
          <p className="text-sm text-muted-foreground" data-testid="recurrence-tx-empty">
            Nenhum gasto consolidado ainda.
          </p>
        )}
        {included.length > 0 && (
          <ul className="border border-border rounded-md overflow-hidden" data-testid="recurrence-transactions">
            {included.map((t) => (
              <li key={t.id} className="flex items-center justify-between gap-2 px-3 py-2.5 border-b border-border last:border-b-0">
                <span className="min-w-0">
                  <span className="block text-[13px] truncate">{t.title}</span>
                  <span className="block text-[11px] text-muted-foreground tabular-nums">{formatDate(t.occurred_at)}</span>
                </span>
                <div className="flex items-center gap-2 shrink-0">
                  <Money cents={t.amount_cents} className="text-[13px]" />
                  <button
                    type="button"
                    onClick={() => exclude.mutate(t.id)}
                    disabled={exclude.isPending}
                    aria-label="Remover do grupo"
                    data-testid={`recurrence-exclude-${t.id}`}
                    className="h-6 w-6 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground disabled:opacity-50"
                  >
                    <X size={13} />
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      {/* Itens removidos do grupo (RF9.7) — restauráveis. */}
      {removed.length > 0 && (
        <section className="space-y-2">
          <span className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground">
            Removidos do grupo
          </span>
          <ul className="border border-border rounded-md overflow-hidden" data-testid="recurrence-removed">
            {removed.map((t) => (
              <li key={t.id} className="flex items-center justify-between gap-2 px-3 py-2.5 border-b border-border last:border-b-0">
                <span className="min-w-0">
                  <span className="block text-[13px] truncate text-muted-foreground">{t.title}</span>
                  <span className="block text-[11px] text-muted-foreground tabular-nums">{formatDate(t.occurred_at)}</span>
                </span>
                <button
                  type="button"
                  onClick={() => include.mutate(t.id)}
                  disabled={include.isPending}
                  data-testid={`recurrence-restore-${t.id}`}
                  className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground disabled:opacity-50 shrink-0"
                >
                  <RotateCcw size={12} /> Restaurar
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* Ajustes (secundário): tolerância + pausar/cancelar. */}
      <section className="border-t border-border pt-4">
        <button
          type="button"
          onClick={() => setShowSettings((v) => !v)}
          className="text-xs text-muted-foreground hover:text-foreground"
          data-testid="recurrence-settings-toggle"
        >
          {showSettings ? 'Ocultar ajustes' : 'Ajustes (tolerância, pausar, cancelar)'}
        </button>

        {showSettings && (
          <div className="mt-3 space-y-4" data-testid="recurrence-settings">
            <label className="block space-y-1">
              <span className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground">
                Tolerância de valor (%)
              </span>
              <Input
                type="number"
                inputMode="numeric"
                value={tolerance}
                onChange={(e) => setTolerance(e.target.value)}
                data-testid="recurrence-tolerance"
              />
              <span className="block text-[11px] text-muted-foreground">
                Variação de valor aceita ao casar novos gastos com esta recorrência —
                usada pra avisar quando a cobrança não chega no prazo.
              </span>
            </label>

            {error && <p className="text-xs text-destructive" role="alert">{error}</p>}

            <div className="flex flex-col gap-2">
              <Button
                onClick={() => run({ amount_tolerance_pct: Number(tolerance) })}
                disabled={update.isPending}
                data-testid="recurrence-save"
              >
                Salvar
              </Button>
              {r.status === 'active' && (
                <Button variant="outline" onClick={() => run({ status: 'paused' })} disabled={update.isPending} data-testid="recurrence-pause">
                  Pausar
                </Button>
              )}
              {r.status === 'paused' && (
                <Button variant="outline" onClick={() => run({ status: 'active' })} disabled={update.isPending} data-testid="recurrence-resume">
                  Retomar
                </Button>
              )}
              <Button variant="destructive" onClick={() => run({ status: 'cancelled' })} disabled={update.isPending} data-testid="recurrence-cancel">
                Cancelar
              </Button>
            </div>
          </div>
        )}
      </section>
    </div>
  )
}
