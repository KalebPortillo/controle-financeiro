import { useEffect, useState } from 'react'
import { Check, X, Trash2, Calendar, Tag as TagIcon, CreditCard } from 'lucide-react'
import { Sheet } from '../components/Sheet'
import { Button } from '../components/Button'
import { Money } from '../components/Money'
import { TagEditor } from './TagEditor'
import {
  useConsolidate,
  useReject,
  useRemoveTransaction,
  useUpdateTransaction,
  type InboxTransaction,
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
}: {
  transaction: InboxTransaction | null
  open: boolean
  onClose: () => void
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

  // Hotkeys A/R quando o sheet está aberto (Esc é tratado pelo Sheet).
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement
      if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return
      if (e.key.toLowerCase() === 'a') accept()
      if (e.key.toLowerCase() === 'r') doReject()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, t?.id])

  return (
    <Sheet open={open} onClose={onClose} width={460}>
      {t && <SheetInner t={t} busy={busy} onClose={onClose} onAccept={accept} onReject={doReject}
                        onUpdate={update.mutate} onRemove={() => remove.mutate(t.id, { onSuccess: onClose })} />}
    </Sheet>
  )
}

function SheetInner({
  t, busy, onClose, onAccept, onReject, onUpdate, onRemove,
}: {
  t: InboxTransaction
  busy: boolean
  onClose: () => void
  onAccept: () => void
  onReject: () => void
  onUpdate: ReturnType<typeof useUpdateTransaction>['mutate']
  onRemove: () => void
}) {
  // Estado local dos campos; re-inicializa só quando muda a transação (key=id).
  const [title, setTitle] = useState(t.improved_title ?? '')
  const [amount, setAmount] = useState((t.amount_cents / 100).toFixed(2))
  const [date, setDate] = useState(t.occurred_at)

  const saveTitle = () => {
    const v = title.trim()
    if (v !== (t.improved_title ?? '')) onUpdate({ id: t.id, lock_version: t.lock_version, improved_title: v })
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

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-6 pt-5 pb-4 border-b border-border">
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
        <FieldLabel>Título</FieldLabel>
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
        <div className="h-9 px-3 flex items-center rounded-md bg-muted text-muted-foreground text-sm truncate">
          {t.account_name ?? '—'}
        </div>

        <FieldLabel icon={<TagIcon size={12} />}>Tags</FieldLabel>
        <TagEditor
          transactionId={t.id}
          current={t.tags}
          disabled={busy}
          onChange={(tagIds) => onUpdate({ id: t.id, lock_version: t.lock_version, tag_ids: tagIds })}
        />

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
      </div>

      {/* Footer */}
      <div className="flex justify-end gap-2 px-5 py-3.5 bg-muted border-t border-border">
        <Button variant="ghost" onClick={onReject} disabled={busy} data-testid={`sheet-reject-${t.id}`}>
          <X size={14} /> Rejeitar
        </Button>
        <Button variant="primary" onClick={onAccept} disabled={busy} data-testid={`sheet-accept-${t.id}`}>
          <Check size={14} /> Aceitar
        </Button>
      </div>
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
