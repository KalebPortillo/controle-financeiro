import { useEffect, useState } from 'react'
import { Check, X, Trash2, Calendar, Tag as TagIcon, CreditCard, Sparkles, ChevronRight, ChevronDown, ArrowLeft } from 'lucide-react'
import { AccountTag } from './AccountTag'
import { InstallmentBadge } from './InstallmentBadge'
import { Sheet } from '../components/Sheet'
import { Button } from '../components/Button'
import { Money } from '../components/Money'
import { TagEditor } from './TagEditor'
import { GhostTagChips } from './GhostTagChips'
import { RefundSection } from './RefundSection'
import {
  useConsolidate,
  useReject,
  useRemoveTransaction,
  useUpdateTransaction,
  useUpdateInstallmentGroup,
  useTransactionEdits,
  useTransactionSource,
  originalToShow,
  type InboxTransaction,
  type TransactionEdit,
  type AiSuggestion,
} from './useInbox'

function signedCents(t: InboxTransaction): number {
  return t.direction === 'debit' ? -t.amount_cents : t.amount_cents
}

/**
 * Detail sheet (RF2.3) — drawer direito pra revisar/editar uma transação da
 * inbox. Recriado do design (ui_kits/app/DetailSheet.jsx). Edições de
 * título/valor/data salvam ao sair do campo (onBlur); tags salvam na hora.
 * Footer: Rejeitar (R) / Aceitar (A); Esc fecha. Categoria/split/estorno entram
 * com RF6/RF10.
 */
export function TransactionDetailSheet({
  transaction: t,
  open,
  onClose,
  onBackToGroup,
  mode = 'inbox',
}: {
  transaction: InboxTransaction | null
  open: boolean
  onClose: () => void
  // Quando a parcela foi aberta a partir do sheet do parcelamento, mostra um
  // "← Parcelamento" pra voltar pro grupo (além do back do navegador).
  onBackToGroup?: () => void
  mode?: 'inbox' | 'consolidated'
}) {
  const consolidate = useConsolidate()
  const reject = useReject()
  const remove = useRemoveTransaction()
  const update = useUpdateTransaction()

  const busy = consolidate.isPending || reject.isPending || remove.isPending || update.isPending

  const accept = () => {
    if (t) consolidate.mutate(t.id, { onSuccess: onClose })
  }
  const doReject = () => {
    if (t) reject.mutate(t.id, { onSuccess: onClose })
  }

  // Hotkeys A/R só no fluxo da inbox (consolidado não aceita/rejeita).
  useEffect(() => {
    if (!open || mode !== 'inbox') return
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement
      if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return
      if (e.key.toLowerCase() === 'a') accept()
      if (e.key.toLowerCase() === 'r') doReject()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, t?.id, mode])

  return (
    <Sheet open={open} onClose={onClose} width={460}>
      {t && <SheetInner t={t} mode={mode} busy={busy} onClose={onClose} onBackToGroup={onBackToGroup} onAccept={accept} onReject={doReject}
                        onUpdate={update.mutate} onRemove={() => remove.mutate(t.id, { onSuccess: onClose })} />}
    </Sheet>
  )
}

function SheetInner({
  t, mode, busy, onClose, onBackToGroup, onAccept, onReject, onUpdate, onRemove,
}: {
  t: InboxTransaction
  mode: 'inbox' | 'consolidated'
  busy: boolean
  onClose: () => void
  onBackToGroup?: () => void
  onAccept: () => void
  onReject: () => void
  onUpdate: ReturnType<typeof useUpdateTransaction>['mutate']
  onRemove: () => void
}) {
  // Estado local dos campos; re-inicializa só quando muda a transação (key=id).
  const [title, setTitle] = useState(t.improved_title ?? '')
  const [amount, setAmount] = useState((t.amount_cents / 100).toFixed(2))
  const [date, setDate] = useState(t.occurred_at)
  const updateGroup = useUpdateInstallmentGroup()

  // RF9.4.1: numa parcela, título e tags valem pro parcelamento inteiro (grupo).
  const groupId = t.installment_group_id
  const isInstallment = t.installment_total != null && groupId != null

  // Salva o título — na parcela vai pro grupo (todas as parcelas), senão à tx.
  const saveTitleValue = (v: string) => {
    if (isInstallment && groupId) updateGroup.mutate({ group_id: groupId, improved_title: v })
    else onUpdate({ id: t.id, lock_version: t.lock_version, improved_title: v })
  }
  const saveTagsValue = (tagIds: string[]) => {
    if (isInstallment && groupId) updateGroup.mutate({ group_id: groupId, tag_ids: tagIds })
    else onUpdate({ id: t.id, lock_version: t.lock_version, tag_ids: tagIds })
  }

  const saveTitle = () => {
    const v = title.trim()
    if (v !== (t.improved_title ?? '')) saveTitleValue(v)
  }
  const saveAmount = () => {
    const cents = Math.round(parseFloat(amount.replace(',', '.')) * 100)
    if (Number.isFinite(cents) && cents > 0 && cents !== t.amount_cents) {
      onUpdate({ id: t.id, lock_version: t.lock_version, amount_cents: cents })
    }
  }
  const saveDate = () => {
    if (date && date !== t.occurred_at) onUpdate({ id: t.id, lock_version: t.lock_version, occurred_at: date })
  }
  // Reverte o título pro texto bruto do banco (sticky — grava em improved_title,
  // não re-dispara IA). Só faz sentido quando o título atual difere do original.
  const canRevert = originalToShow(t) !== null
  const revertToOriginal = () => {
    setTitle(t.original_description)
    saveTitleValue(t.original_description)
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-6 pt-5 pb-4 border-b border-border">
        {onBackToGroup && (
          <button
            onClick={onBackToGroup}
            className="inline-flex items-center gap-1 mb-2.5 text-xs text-muted-foreground hover:text-foreground"
            data-testid="back-to-group"
          >
            <ArrowLeft size={13} /> Parcelamento
          </button>
        )}
        <div className="flex items-start gap-2.5">
          <div className="flex-1 min-w-0">
            <div className="font-display text-lg font-semibold tracking-tight mb-1 truncate">
              {t.improved_title || t.original_description}
            </div>
            <div className="text-xs text-muted-foreground">
              Descrição bruta: <span className="font-mono">{t.original_description}</span>
            </div>
          </div>
          <button
            onClick={onClose}
            aria-label="Fechar"
            className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground shrink-0"
          >
            <X size={16} />
          </button>
        </div>
        <div className="mt-3.5">
          <Money cents={signedCents(t)} signed className="text-3xl font-medium" />
        </div>
      </div>

      {/* Body */}
      <div className="flex-1 overflow-y-auto px-6 py-5 flex flex-col gap-3.5">
        <div className="flex items-center justify-between gap-2">
          <FieldLabel>Título</FieldLabel>
          {canRevert && (
            <button
              type="button"
              onClick={revertToOriginal}
              disabled={busy}
              className="text-[11px] text-muted-foreground hover:text-foreground underline"
              data-testid={`sheet-use-original-${t.id}`}
            >
              usar título original
            </button>
          )}
        </div>
        <Input value={title} onChange={setTitle} onBlur={saveTitle} testid={`sheet-title-${t.id}`} />

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <FieldLabel>Valor</FieldLabel>
            <Input value={amount} onChange={setAmount} onBlur={saveAmount} mono inputMode="decimal" testid={`sheet-amount-${t.id}`} />
          </div>
          <div className="space-y-1.5">
            <FieldLabel icon={<Calendar size={12} />}>Data</FieldLabel>
            <Input type="date" value={date} onChange={setDate} onBlur={saveDate} testid={`sheet-date-${t.id}`} />
          </div>
        </div>

        <FieldLabel icon={<CreditCard size={12} />}>Conta</FieldLabel>
        <div className="h-9 px-3 flex items-center gap-1.5 rounded-md bg-muted text-muted-foreground text-sm truncate">
          <AccountTag t={t} />
          {t.installment_total && (
            <>
              <span className="text-border">·</span>
              <InstallmentBadge number={t.installment_number} total={t.installment_total} />
            </>
          )}
        </div>

        <FieldLabel icon={<TagIcon size={12} />}>Tags</FieldLabel>
        <TagEditor
          transactionId={t.id}
          current={t.tags}
          disabled={busy}
          onChange={saveTagsValue}
        />
        {isInstallment && (
          <p className="text-[11px] text-muted-foreground -mt-1.5" data-testid="installment-group-note">
            Título e tags valem para as {t.installment_total} parcelas deste parcelamento.
          </p>
        )}
        {/* Chips fantasma: tags sugeridas pela IA, ainda não aceitas (RF3). */}
        {mode === 'inbox' && t.ai_suggestion && t.ai_suggestion.new_tags.length > 0 && (
          <GhostTagChips transactionId={t.id} suggestedNames={t.ai_suggestion.new_tags} />
        )}

        <div className="flex flex-col items-start gap-2 mt-2 pt-3.5 border-t border-border">
          <button
            onClick={onRemove}
            disabled={busy}
            className="inline-flex items-center gap-1.5 text-sm text-destructive hover:underline"
            data-testid={`sheet-remove-${t.id}`}
          >
            <Trash2 size={12} /> Excluir definitivamente
          </button>
        </div>

        {/* RF10 — vincular/exibir estorno. */}
        <RefundSection transaction={t} />

        <ActivityTimeline transactionId={t.id} aiSuggestion={t.ai_suggestion} />

        {/* RF2.7 — payload cru do Pluggy, sob demanda. Só p/ gastos sincronizados. */}
        {t.source === 'automatic_sync' && <SourceDetails transactionId={t.id} />}
      </div>

      {/* Footer */}
      <div className="flex justify-end gap-2 px-5 py-3.5 bg-muted border-t border-border">
        {mode === 'inbox' ? (
          <>
            <Button variant="ghost" onClick={onReject} disabled={busy} data-testid={`sheet-reject-${t.id}`}>
              <X size={14} /> Rejeitar
            </Button>
            <Button variant="primary" onClick={onAccept} disabled={busy} data-testid={`sheet-accept-${t.id}`}>
              <Check size={14} /> Aceitar
            </Button>
          </>
        ) : (
          <Button variant="outline" onClick={onClose} data-testid={`sheet-done-${t.id}`}>
            Concluído
          </Button>
        )}
      </div>
    </div>
  )
}

const FIELD_LABELS: Record<string, string> = {
  improved_title: 'Título',
  amount_cents: 'Valor',
  occurred_at: 'Data',
  tags: 'Tags',
}

function formatEditValue(field: string, value: unknown): string {
  if (value === null || value === undefined || value === '') return '—'
  if (field === 'amount_cents' && typeof value === 'number') {
    return (value / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
  }
  if (field === 'tags' && Array.isArray(value)) return `${value.length} tag(s)`
  return String(value)
}

function relativeTime(iso: string): string {
  const min = Math.round((Date.now() - new Date(iso).getTime()) / 60000)
  if (min < 1) return 'agora'
  if (min < 60) return `há ${min} min`
  const h = Math.round(min / 60)
  if (h < 24) return `há ${h} h`
  return `há ${Math.round(h / 24)} d`
}

// Timeline unificada: sugestão da IA + alterações do usuário (RF3 + RF4.3).
function ActivityTimeline({
  transactionId,
  aiSuggestion,
}: {
  transactionId: string
  aiSuggestion: AiSuggestion
}) {
  const [open, setOpen] = useState(false)
  const { data: edits, isLoading } = useTransactionEdits(transactionId, open)

  const hasActivity = aiSuggestion || (edits?.length ?? 0) > 0

  return (
    <div className="mt-2 pt-3.5 border-t border-border">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="text-xs text-muted-foreground hover:text-foreground"
        data-testid={`history-toggle-${transactionId}`}
      >
        {open ? 'Ocultar histórico' : 'Histórico e sugestões da IA'}
      </button>

      {open && (
        <div className="mt-3 space-y-3" data-testid={`history-${transactionId}`}>
          {/* Sugestão da IA */}
          {aiSuggestion && (
            <div className="flex gap-2.5">
              <div className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-violet-100 text-violet-600">
                <Sparkles size={11} />
              </div>
              <div className="text-[11px]">
                <span className="font-medium text-foreground">IA sugeriu</span>
                <span className="text-muted-foreground"> · {relativeTime(aiSuggestion.suggested_at)}</span>
                <div className="mt-0.5 text-muted-foreground space-y-0.5">
                  {aiSuggestion.title && (
                    <div>Título: <span className="text-foreground">"{aiSuggestion.title}"</span></div>
                  )}
                  {aiSuggestion.tag_names.length > 0 && (
                    <div>Tags: <span className="text-foreground">{aiSuggestion.tag_names.join(', ')}</span></div>
                  )}
                  {aiSuggestion.new_tags.length > 0 && (
                    <div>Tags criadas: <span className="text-foreground">{aiSuggestion.new_tags.join(', ')}</span></div>
                  )}
                  <div className="text-[10px]">
                    Confiança: {aiSuggestion.confidence === 'high' ? 'alta' : aiSuggestion.confidence === 'medium' ? 'média' : 'baixa'}
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Alterações do usuário */}
          {isLoading && <p className="text-[11px] text-muted-foreground">Carregando…</p>}
          {!isLoading && !hasActivity && (
            <p className="text-[11px] text-muted-foreground">Sem atividade ainda.</p>
          )}
          {edits?.map((e: TransactionEdit) => (
            <div key={e.id} className="flex gap-2.5">
              <div className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-muted border border-border text-muted-foreground text-[10px] font-bold">
                {e.edited_by.name.charAt(0).toUpperCase()}
              </div>
              <div className="text-[11px]">
                <span className="font-medium text-foreground">{e.edited_by.name}</span>
                <span className="text-muted-foreground"> alterou {FIELD_LABELS[e.field_name] ?? e.field_name}</span>
                <span className="block text-[10px] text-muted-foreground">{relativeTime(e.edited_at)}</span>
                <div className="mt-0.5 text-[11px] text-muted-foreground">
                  {formatEditValue(e.field_name, e.old_value)} → {formatEditValue(e.field_name, e.new_value)}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function FieldLabel({ icon, children }: { icon?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-1.5 text-[11px] uppercase tracking-wider font-medium text-muted-foreground">
      {icon}
      <span>{children}</span>
    </div>
  )
}

// RF2.7 — "exibir mais detalhes": payload cru do Pluggy, formatado, sob demanda.
function SourceDetails({ transactionId }: { transactionId: string }) {
  const [open, setOpen] = useState(false)
  const { data, isLoading } = useTransactionSource(transactionId, open)

  return (
    <div className="border-t border-border pt-3">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-1 text-[11px] uppercase tracking-wider font-medium text-muted-foreground hover:text-foreground"
        data-testid={`source-toggle-${transactionId}`}
      >
        {open ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
        Exibir mais detalhes
      </button>
      {open && (
        <div className="mt-2" data-testid={`source-${transactionId}`}>
          {isLoading && <p className="text-[11px] text-muted-foreground">Carregando…</p>}
          {data && (
            <pre className="max-h-72 overflow-auto rounded-md border border-border bg-muted p-3 text-[11px] leading-relaxed font-mono whitespace-pre-wrap break-words">
              {JSON.stringify(data.source_metadata, null, 2)}
            </pre>
          )}
        </div>
      )}
    </div>
  )
}

function Input({
  value, onChange, onBlur, mono, type, inputMode, testid,
}: {
  value: string
  onChange: (v: string) => void
  onBlur: () => void
  mono?: boolean
  type?: string
  inputMode?: 'decimal'
  testid?: string
}) {
  return (
    <input
      type={type}
      inputMode={inputMode}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      onBlur={onBlur}
      data-testid={testid}
      className={`h-9 w-full rounded-md border border-input bg-background px-3 text-sm text-foreground focus:border-ring focus:outline-2 focus:outline-ring/30 ${mono ? 'cf-money' : ''}`}
    />
  )
}
