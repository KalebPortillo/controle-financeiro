import { useState, useEffect, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { CreditCard, Check, CheckSquare, Sparkles, CircleSlash, Loader2 } from 'lucide-react'
import { Button } from '../components/Button'
import { Money } from '../components/Money'
import { TagChip } from '../components/TagChip'
import {
  useInbox,
  useConsolidate,
  useReject,
  useReanalyzeInbox,
  type InboxTransaction,
  type AiConfidence,
} from './useInbox'
import { useAnalysisProgress } from './useAnalysisProgress'
import { TransactionDetailSheet } from './TransactionDetailSheet'
import { SwipeableRow } from './SwipeableRow'
import { Alert } from '../components/Alert'

function AiConfidenceBadge({ confidence }: { confidence: AiConfidence }) {
  if (!confidence) return null
  const styles: Record<NonNullable<AiConfidence>, string> = {
    high:   'bg-green-50 text-green-700 border-green-200',
    medium: 'bg-yellow-50 text-yellow-700 border-yellow-200',
    low:    'bg-red-50 text-red-700 border-red-200',
  }
  const labels: Record<NonNullable<AiConfidence>, string> = {
    high: 'IA', medium: 'IA?', low: 'IA?'
  }
  return (
    <span className={`inline-flex items-center rounded-sm border px-1 py-0 text-[10px] font-medium ${styles[confidence]}`}>
      {labels[confidence]}
    </span>
  )
}

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

  const reanalyze = useReanalyzeInbox()
  const qc = useQueryClient()
  // Progresso REAL da análise IA por estado (ai_status). `analyzing` = há gastos
  // aguardando; `failed` = a IA não conseguiu (não trava o progresso).
  const progress = useAnalysisProgress(true)
  const analyzing = progress.analyzing

  // Quando a análise termina (done passa a true), recarrega a inbox pra puxar
  // os títulos/tags recém-sugeridos.
  const wasAnalyzing = useRef(false)
  useEffect(() => {
    if (analyzing) wasAnalyzing.current = true
    else if (wasAnalyzing.current) {
      wasAnalyzing.current = false
      qc.invalidateQueries({ queryKey: ['transactions'] })
    }
  }, [analyzing, qc])

  const handleReanalyze = () => {
    reanalyze.mutate(undefined, {
      // Refaz a leitura do progresso pra barra reagir ao novo lote enfileirado.
      onSettled: () => qc.invalidateQueries({ queryKey: ['transactions', 'analysis_progress'] }),
    })
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
        {(data?.pending_count ?? 0) > 0 && (
          <Button
            variant="outline"
            size="sm"
            onClick={handleReanalyze}
            disabled={analyzing || reanalyze.isPending}
            data-testid="reanalyze-btn"
          >
            {analyzing
              ? <Loader2 size={14} className="animate-spin" />
              : <Sparkles size={14} />}
            {analyzing
              ? `Analisando… ${progress.analyzed}/${progress.total}`
              : 'Reanalisar com IA'}
          </Button>
        )}
      </div>

      {analyzing && (
        <div className="mb-4 space-y-1" data-testid="analysis-progress">
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
            <div
              className="h-full rounded-full bg-accent transition-all duration-500 ease-out"
              style={{ width: `${Math.round(progress.pct * 100)}%` }}
              data-testid="analysis-progress-bar"
            />
          </div>
          <p className="text-[11px] text-muted-foreground">
            Analisando com IA · {progress.analyzed} de {progress.total} ({Math.round(progress.pct * 100)}%)
          </p>
        </div>
      )}

      {/* Concluído mas com gastos que a IA não conseguiu analisar (não estão mais
          aguardando). Some quando voltam a ser analisados. */}
      {!analyzing && progress.failed > 0 && (
        <Alert
          variant="warning"
          title={`${progress.failed} ${progress.failed === 1 ? 'gasto não foi analisado' : 'gastos não foram analisados'} pela IA`}
          testid="ai-failed-banner"
          className="mb-4"
          action={
            <Button
              variant="outline"
              size="sm"
              onClick={handleReanalyze}
              disabled={reanalyze.isPending}
              data-testid="ai-error-retry"
            >
              Tentar de novo
            </Button>
          }
        >
          {progress.error?.message ?? 'Você pode tentar de novo ou organizá-los manualmente.'}
        </Alert>
      )}

      {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}
      {!isLoading && transactions.length === 0 && (
        <p className="text-sm text-muted-foreground" data-testid="inbox-empty">
          Nada pendente. Tudo revisado.
        </p>
      )}

      {transactions.length > 0 && (
        <div className="border border-border rounded-lg overflow-hidden">
          <div className="hidden md:grid grid-cols-[32px_1fr_150px_110px] gap-3 px-4 py-2 text-[11px] uppercase tracking-wider font-medium text-muted-foreground border-b border-border">
            <span />
            <span>Descrição</span>
            <span>Tags</span>
            <span className="text-right">Valor</span>
          </div>

          {transactions.map((t) => (
            <SwipeableRow
              key={t.id}
              testid={`inbox-row-${t.id}`}
              swipeLeft={{
                onAction: () => consolidate.mutate(t.id),
                label: 'Aceitar',
                icon: <Check size={16} />,
                idleClass: 'bg-success/30 text-success',
                armedClass: 'bg-[var(--success-vivid)] text-white',
              }}
              swipeRight={{
                onAction: () => toggle(t.id),
                label: selected.has(t.id) ? 'Desmarcar' : 'Selecionar',
                icon: <CheckSquare size={16} />,
                idleClass: 'bg-accent/30 text-accent',
                armedClass: 'bg-accent text-accent-foreground',
              }}
              onClick={() => open(t)}
            >
              <RowContent
                t={t}
                selected={selected.has(t.id)}
                active={activeId === t.id && sheetOpen}
                onToggle={() => toggle(t.id)}
              />
            </SwipeableRow>
          ))}
        </div>
      )}

      {selected.size > 0 && (
        <div className="sticky bottom-4 md:bottom-4 mt-4 flex flex-wrap items-center justify-between gap-2 px-4 py-3 bg-card border border-border rounded-lg shadow-[var(--shadow-lg)]">
          <div className="flex items-center gap-2.5 text-sm font-medium min-w-0">
            {selected.size} selecionado{selected.size > 1 ? 's' : ''}
            <button
              onClick={() => setSelected(new Set())}
              className="text-xs text-muted-foreground underline shrink-0"
            >
              limpar
            </button>
          </div>
          <div className="flex gap-2 shrink-0">
            <Button variant="ghost" size="sm" onClick={bulkReject} disabled={busy} data-testid="bulk-reject">
              Rejeitar
            </Button>
            <Button variant="primary" size="sm" onClick={bulkAccept} disabled={busy} data-testid="bulk-accept">
              Aceitar ({selected.size})
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

function RowContent({
  t, selected, active, onToggle,
}: {
  t: InboxTransaction
  selected: boolean
  active: boolean
  onToggle: () => void
}) {
  return (
    <div
      className={`grid grid-cols-[28px_1fr_auto] md:grid-cols-[32px_1fr_150px_110px] gap-3 items-center px-4 py-3 transition-colors hover:bg-muted ${
        active ? 'bg-muted shadow-[inset_2px_0_0_0_var(--accent)]' : ''
      } ${selected ? 'bg-[color-mix(in_srgb,var(--accent)_6%,transparent)]' : ''}`}
    >
      {/* checkbox não inicia swipe nem abre o detalhe */}
      <label
        className="flex items-center"
        onClick={(e) => e.stopPropagation()}
        onPointerDown={(e) => e.stopPropagation()}
      >
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
        <div className="flex items-center gap-1.5 truncate">
          <span className="text-[13px] font-medium truncate">
            {t.improved_title || (
              <span className="font-mono text-muted-foreground">{t.original_description}</span>
            )}
          </span>
          {t.ai_confidence && <AiConfidenceBadge confidence={t.ai_confidence} />}
          {t.ai_status === 'failed' && (
            <span
              className="inline-flex items-center gap-1 rounded-sm border border-warning/40 bg-warning/10 px-1 py-0 text-[10px] font-medium text-warning"
              data-testid={`not-analyzed-${t.id}`}
              title="A IA não conseguiu analisar este gasto"
            >
              <CircleSlash size={10} /> não analisado
            </span>
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
