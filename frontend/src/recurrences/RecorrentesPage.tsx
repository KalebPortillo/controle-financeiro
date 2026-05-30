import { useState } from 'react'
import { Money } from '../components/Money'
import { Badge } from '../components/Badge'
import { Button } from '../components/Button'
import { Input } from '../components/Input'
import { Sheet } from '../components/Sheet'
import { ApiError } from '../api/client'
import {
  useRecurrences,
  useUpdateRecurrence,
  CADENCE_LABELS,
  type Recurrence,
  type RecurrenceUpdate,
} from './useRecurrences'

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

  // Canceladas saem da lista — viram histórico, não item ativo.
  const visible = (recurrences ?? []).filter((r) => r.status !== 'cancelled')

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <section className="space-y-1">
        <h1 className="font-sans text-2xl font-semibold tracking-tight">Recorrentes</h1>
        <p className="text-sm text-muted-foreground">
          Assinaturas e contas fixas detectadas no histórico ou cadastradas por você.
        </p>
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
  const [tolerance, setTolerance] = useState(String(r.amount_tolerance_pct))
  const [error, setError] = useState<string | null>(null)

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
        </div>
        <p className="text-sm text-muted-foreground">
          {CADENCE_LABELS[r.cadence]} · próximo {formatDate(r.next_expected_at)}
        </p>
      </div>

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
      </label>

      {error && (
        <p className="text-xs text-destructive" role="alert">
          {error}
        </p>
      )}

      <div className="flex flex-col gap-2">
        <Button
          onClick={() => run({ amount_tolerance_pct: Number(tolerance) })}
          disabled={update.isPending}
          data-testid="recurrence-save"
        >
          Salvar
        </Button>
        {r.status === 'active' && (
          <Button
            variant="outline"
            onClick={() => run({ status: 'paused' })}
            disabled={update.isPending}
            data-testid="recurrence-pause"
          >
            Pausar
          </Button>
        )}
        {r.status === 'paused' && (
          <Button
            variant="outline"
            onClick={() => run({ status: 'active' })}
            disabled={update.isPending}
            data-testid="recurrence-resume"
          >
            Retomar
          </Button>
        )}
        <Button
          variant="destructive"
          onClick={() => run({ status: 'cancelled' })}
          disabled={update.isPending}
          data-testid="recurrence-cancel"
        >
          Cancelar
        </Button>
      </div>
    </div>
  )
}
