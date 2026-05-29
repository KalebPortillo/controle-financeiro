import { useState } from 'react'
import { Sheet } from '../components/Sheet'
import { Button } from '../components/Button'
import { TagEditor } from './TagEditor'
import { useCreateManualTransaction, type InboxTag } from './useInbox'
import { useTags } from './useTags'

function today(): string {
  return new Date().toISOString().slice(0, 10)
}

/**
 * Lançamento manual (RF12) — gasto/receita do zero, direto pra consolidados.
 * Tipo, valor, data, título e tags. Origem fixa "Dinheiro / Externo" (slice 1).
 */
export function ManualEntrySheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const create = useCreateManualTransaction()
  const { data: allTags } = useTags()

  const [direction, setDirection] = useState<'debit' | 'credit'>('debit')
  const [amount, setAmount] = useState('')
  const [date, setDate] = useState(today())
  const [title, setTitle] = useState('')
  const [selected, setSelected] = useState<InboxTag[]>([])

  const reset = () => {
    setDirection('debit'); setAmount(''); setDate(today()); setTitle(''); setSelected([])
  }

  const onTagsChange = (ids: string[]) => {
    const map = new Map((allTags ?? []).map((t) => [t.id, t]))
    setSelected(ids.flatMap((id) => {
      const t = map.get(id)
      return t ? [{ id: t.id, name: t.name, color: t.color, icon: t.icon }] : []
    }))
  }

  const cents = Math.round(parseFloat(amount.replace(',', '.')) * 100)
  const valid = Number.isFinite(cents) && cents > 0 && !!date

  const submit = () => {
    if (!valid) return
    create.mutate(
      {
        direction,
        amount_cents: cents,
        occurred_at: date,
        improved_title: title.trim() || undefined,
        tag_ids: selected.map((t) => t.id),
      },
      { onSuccess: () => { reset(); onClose() } }
    )
  }

  return (
    <Sheet open={open} onClose={onClose} width={460}>
      <div className="flex flex-col h-full">
        <div className="px-6 pt-5 pb-4 border-b border-border">
          <h2 className="font-display text-lg font-semibold tracking-tight">Lançar manualmente</h2>
          <p className="text-xs text-muted-foreground mt-1">
            Dinheiro, PicPay, presentes — vai direto pros consolidados.
          </p>
        </div>

        <div className="flex-1 overflow-y-auto px-6 py-5 flex flex-col gap-3.5">
          <div className="inline-flex rounded-md border border-border overflow-hidden w-fit">
            <button
              type="button"
              onClick={() => setDirection('debit')}
              data-testid="manual-type-debit"
              className={`px-3 py-1.5 text-sm ${direction === 'debit' ? 'bg-primary text-primary-foreground' : 'text-foreground'}`}
            >
              Gasto
            </button>
            <button
              type="button"
              onClick={() => setDirection('credit')}
              data-testid="manual-type-credit"
              className={`px-3 py-1.5 text-sm ${direction === 'credit' ? 'bg-primary text-primary-foreground' : 'text-foreground'}`}
            >
              Receita
            </button>
          </div>

          <Field label="Valor">
            <input
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              inputMode="decimal"
              placeholder="0,00"
              data-testid="manual-amount"
              className="h-9 w-full rounded-md border border-input bg-background px-3 text-sm cf-money focus:border-ring focus:outline-2 focus:outline-ring/30"
            />
          </Field>

          <Field label="Data">
            <input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              data-testid="manual-date"
              className="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus:border-ring focus:outline-2 focus:outline-ring/30"
            />
          </Field>

          <Field label="Título">
            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="ex.: Almoço, Presente"
              data-testid="manual-title"
              className="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus:border-ring focus:outline-2 focus:outline-ring/30"
            />
          </Field>

          <Field label="Tags">
            <TagEditor transactionId="manual" current={selected} onChange={onTagsChange} />
          </Field>
        </div>

        <div className="flex justify-end gap-2 px-5 py-3.5 bg-muted border-t border-border">
          <Button variant="ghost" onClick={onClose} disabled={create.isPending}>Cancelar</Button>
          <Button variant="primary" onClick={submit} disabled={!valid || create.isPending} data-testid="manual-submit">
            {create.isPending ? 'Lançando…' : 'Lançar'}
          </Button>
        </div>
      </div>
    </Sheet>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground">{label}</div>
      {children}
    </div>
  )
}
