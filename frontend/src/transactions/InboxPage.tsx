import { useState } from 'react'
import { CreditCard } from 'lucide-react'
import { Button } from '../components/Button'
import { Money } from '../components/Money'
import { TagChip } from '../components/TagChip'
import {
  useInbox,
  useConsolidate,
  useReject,
  type InboxTransaction,
} from './useInbox'
import { TransactionDetailSheet } from './TransactionDetailSheet'

function formatDate(iso: string): string {
  const [, m, d] = iso.split('-')
  return `${d}/${m}`
}

function signedCents(t: InboxTransaction): number {
  return t.direction === 'debit' ? -t.amount_cents : t.amount_cents
}

/**
 * Inbox (RF2) — tabela densa das transações pendentes (status pending) no padrão
 * do design (ui_kits/app/InboxView.jsx). Clicar numa linha abre o detail sheet;
 * seleção múltipla expõe a barra de ações em massa.
 */
export function InboxPage() {
  const { data, isLoading } = useInbox()
  const consolidate = useConsolidate()
  const reject = useReject()

  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [activeId, setActiveId] = useState<string | null>(null)
  const [sheetOpen, setSheetOpen] = useState(false)

  const transactions = data?.transactions ?? []
  const active = transactions.find((t) => t.id === activeId) ?? null

  const toggle = (id: string) =>
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })

  const open = (t: InboxTransaction) => {
    setActiveId(t.id)
    setSheetOpen(true)
  }

  const bulkAccept = async () => {
    await Promise.all([...selected].map((id) => consolidate.mutateAsync(id)))
    setSelected(new Set())
  }
  const bulkReject = async () => {
    await Promise.all([...selected].map((id) => reject.mutateAsync(id)))
    setSelected(new Set())
  }

  const busy = consolidate.isPending || reject.isPending

  return (
    <div className="max-w-4xl mx-auto">
      <div className="flex items-end justify-between mb-4">
        <div>
          <h1 className="font-sans text-2xl font-semibold tracking-tight">Inbox</h1>
          <p className="text-xs text-muted-foreground mt-0.5">
            {data?.pending_count ?? 0} pendente{(data?.pending_count ?? 0) === 1 ? '' : 's'} esperando revisão
          </p>
        </div>
      </div>

      {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}
      {!isLoading && transactions.length === 0 && (
        <p className="text-sm text-muted-foreground" data-testid="inbox-empty">
          Nada pendente. Tudo revisado.
        </p>
      )}

      {transactions.length > 0 && (
        <div className="border border-border rounded-lg overflow-hidden">
          <div className="hidden md:grid grid-cols-[32px_1fr_180px_120px] gap-3 px-4 py-2 text-[11px] uppercase tracking-wider font-medium text-muted-foreground border-b border-border">
            <span />
            <span>Descrição</span>
            <span>Tags</span>
            <span className="text-right">Valor</span>
          </div>

          {transactions.map((t) => (
            <Row
              key={t.id}
              t={t}
              selected={selected.has(t.id)}
              active={activeId === t.id && sheetOpen}
              onToggle={() => toggle(t.id)}
              onOpen={() => open(t)}
            />
          ))}
        </div>
      )}

      {selected.size > 0 && (
        <div className="sticky bottom-4 mt-4 flex items-center justify-between gap-3 px-4 py-3 bg-card border border-border rounded-lg shadow-[var(--shadow-lg)]">
          <div className="flex items-center gap-2.5 text-sm font-medium">
            {selected.size} selecionado{selected.size > 1 ? 's' : ''}
            <button
              onClick={() => setSelected(new Set())}
              className="text-xs text-muted-foreground underline"
            >
              limpar
            </button>
          </div>
          <div className="flex gap-2">
            <Button variant="ghost" onClick={bulkReject} disabled={busy} data-testid="bulk-reject">
              Rejeitar
            </Button>
            <Button variant="primary" onClick={bulkAccept} disabled={busy} data-testid="bulk-accept">
              Aceitar selecionados ({selected.size})
            </Button>
          </div>
        </div>
      )}

      <TransactionDetailSheet
        transaction={active}
        open={sheetOpen}
        onClose={() => setSheetOpen(false)}
      />
    </div>
  )
}

function Row({
  t, selected, active, onToggle, onOpen,
}: {
  t: InboxTransaction
  selected: boolean
  active: boolean
  onToggle: () => void
  onOpen: () => void
}) {
  return (
    <div
      onClick={onOpen}
      data-testid={`inbox-row-${t.id}`}
      className={`grid grid-cols-[32px_1fr_auto] md:grid-cols-[32px_1fr_180px_120px] gap-3 items-center px-4 py-3 border-b border-border last:border-b-0 cursor-pointer transition-colors hover:bg-muted ${
        active ? 'bg-muted shadow-[inset_2px_0_0_0_var(--accent)]' : ''
      } ${selected ? 'bg-[color-mix(in_srgb,var(--accent)_6%,transparent)]' : ''}`}
    >
      <label className="flex items-center" onClick={(e) => e.stopPropagation()}>
        <input
          type="checkbox"
          checked={selected}
          onChange={onToggle}
          aria-label="Selecionar"
          className="cursor-pointer accent-[var(--accent)]"
          data-testid={`select-${t.id}`}
        />
      </label>

      <div className="min-w-0">
        <div className="text-[13px] font-medium truncate">
          {t.improved_title || (
            <span className="font-mono text-muted-foreground">{t.original_description}</span>
          )}
        </div>
        <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground mt-0.5">
          <CreditCard size={12} />
          <span className="truncate">{t.account_name ?? '—'}</span>
          <span className="text-border">·</span>
          <span>{formatDate(t.occurred_at)}</span>
        </div>
        {t.tags.length > 0 && (
          <div className="flex md:hidden items-center gap-1.5 mt-1.5 overflow-hidden">
            {t.tags.slice(0, 2).map((tag) => (
              <TagChip key={tag.id} name={tag.name} color={tag.color} />
            ))}
            {t.tags.length > 2 && <span className="text-[11px] text-muted-foreground">+{t.tags.length - 2}</span>}
          </div>
        )}
      </div>

      <div className="hidden md:flex items-center gap-1.5 overflow-hidden">
        {t.tags.slice(0, 2).map((tag) => (
          <TagChip key={tag.id} name={tag.name} color={tag.color} />
        ))}
        {t.tags.length > 2 && <span className="text-[11px] text-muted-foreground">+{t.tags.length - 2}</span>}
      </div>

      <div className="text-right whitespace-nowrap">
        <Money cents={signedCents(t)} signed className="font-semibold" />
      </div>
    </div>
  )
}
