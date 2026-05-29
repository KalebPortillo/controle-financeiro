import { useState } from 'react'
import { CreditCard, ChevronLeft, ChevronRight } from 'lucide-react'
import { Money } from '../components/Money'
import { TagChip } from '../components/TagChip'
import { useConsolidated, type InboxTransaction } from './useInbox'
import { TransactionDetailSheet } from './TransactionDetailSheet'

const MONTHS = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

function currentPeriod(): string {
  const now = new Date()
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`
}

function shiftPeriod(period: string, delta: number): string {
  const [y, m] = period.split('-').map(Number)
  const d = new Date(y, m - 1 + delta, 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

function periodLabel(period: string): string {
  const [y, m] = period.split('-').map(Number)
  return `${MONTHS[m - 1]} · ${y}`
}

function formatDate(iso: string): string {
  const [, m, d] = iso.split('-')
  return `${d}/${m}`
}

function signedCents(t: InboxTransaction): number {
  return t.direction === 'debit' ? -t.amount_cents : t.amount_cents
}

/**
 * Gastos consolidados (RF4) — o que foi aceito da inbox, por mês. Totais de
 * gasto/receita, navegação de período, e edição/remoção via detail sheet.
 * Recriado do design (ui_kits/app/GastosView.jsx).
 */
export function GastosPage() {
  const [period, setPeriod] = useState(currentPeriod())
  const { data, isLoading } = useConsolidated(period)
  const [activeId, setActiveId] = useState<string | null>(null)
  const [sheetOpen, setSheetOpen] = useState(false)

  const txs = data?.transactions ?? []
  const active = txs.find((t) => t.id === activeId) ?? null

  const spent = txs.filter((t) => t.direction === 'debit').reduce((s, t) => s + t.amount_cents, 0)
  const received = txs.filter((t) => t.direction === 'credit').reduce((s, t) => s + t.amount_cents, 0)

  return (
    <div className="max-w-4xl mx-auto">
      <div className="flex items-end justify-between mb-4">
        <div>
          <div className="text-xs text-muted-foreground">{periodLabel(period)} · todas as contas</div>
          <h1 className="font-sans text-2xl font-semibold tracking-tight mt-1">Gastos consolidados</h1>
        </div>
        <div className="flex items-center gap-1">
          <button
            onClick={() => setPeriod((p) => shiftPeriod(p, -1))}
            aria-label="Mês anterior"
            data-testid="prev-month"
            className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted"
          >
            <ChevronLeft size={16} />
          </button>
          <span className="text-sm font-medium w-24 text-center">{periodLabel(period)}</span>
          <button
            onClick={() => setPeriod((p) => shiftPeriod(p, 1))}
            aria-label="Próximo mês"
            data-testid="next-month"
            className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted"
          >
            <ChevronRight size={16} />
          </button>
        </div>
      </div>

      <div className="flex flex-wrap items-baseline gap-x-6 gap-y-1 mb-4">
        <div>
          <Money cents={-spent} className="text-xl font-semibold" />
          <span className="text-xs text-muted-foreground ml-2">
            em {txs.filter((t) => t.direction === 'debit').length} gastos
          </span>
        </div>
        {received > 0 && (
          <div className="text-sm">
            <span className="text-xs text-muted-foreground">Receita</span>{' '}
            <Money cents={received} signed className="font-semibold" />
          </div>
        )}
      </div>

      {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}
      {!isLoading && txs.length === 0 && (
        <p className="text-sm text-muted-foreground" data-testid="gastos-empty">
          Nenhum gasto consolidado em {periodLabel(period)}.
        </p>
      )}

      {txs.length > 0 && (
        <div className="border border-border rounded-lg overflow-hidden">
          <div className="hidden md:grid grid-cols-[1fr_150px_110px] gap-3 px-4 py-2 text-[11px] uppercase tracking-wider font-medium text-muted-foreground border-b border-border">
            <span>Descrição</span>
            <span>Tags</span>
            <span className="text-right">Valor</span>
          </div>
          {txs.map((t) => (
            <button
              key={t.id}
              onClick={() => { setActiveId(t.id); setSheetOpen(true) }}
              data-testid={`gasto-row-${t.id}`}
              className="grid w-full text-left grid-cols-[1fr_auto] md:grid-cols-[1fr_150px_110px] gap-3 items-center px-4 py-3 border-b border-border last:border-b-0 hover:bg-muted transition-colors"
            >
              <div className="min-w-0">
                <div className="text-[13px] font-medium truncate">
                  {t.improved_title || t.original_description}
                </div>
                <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground mt-0.5">
                  <CreditCard size={12} />
                  <span className="truncate">{t.account_name ?? '—'}</span>
                  <span className="text-border">·</span>
                  <span>{formatDate(t.occurred_at)}</span>
                </div>
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
            </button>
          ))}
        </div>
      )}

      <TransactionDetailSheet
        transaction={active}
        open={sheetOpen}
        onClose={() => setSheetOpen(false)}
        mode="consolidated"
      />
    </div>
  )
}
