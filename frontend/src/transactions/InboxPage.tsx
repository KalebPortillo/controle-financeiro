import { useState } from 'react'
import { Link } from 'react-router'
import { WalletLogo } from '../components/WalletLogo'
import { Button } from '../components/Button'
import { Input } from '../components/Input'
import { Card, CardBody } from '../components/Card'
import {
  useInbox,
  useConsolidate,
  useReject,
  useRemoveTransaction,
  useUpdateTransaction,
  type InboxTransaction,
} from './useInbox'

function formatMoney(cents: number, currency = 'BRL'): string {
  return (cents / 100).toLocaleString('pt-BR', { style: 'currency', currency })
}

function formatDate(iso: string): string {
  const [, m, d] = iso.split('-')
  return `${d}/${m}`
}

/**
 * Inbox (RF2) — revisa as transações que o sync trouxe (status pending) antes de
 * consolidar. Ações por item: aceitar, rejeitar, editar (título/valor), remover.
 * Tags/categoria/split entram quando RF5/RF6/RF10 existirem.
 */
export function InboxPage() {
  const { data, isLoading } = useInbox()

  return (
    <main className="min-h-screen bg-background text-foreground">
      <header className="border-b border-border bg-card">
        <div className="max-w-3xl mx-auto px-4 h-14 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-2 text-foreground">
            <WalletLogo size={20} />
            <span className="font-sans text-sm font-medium">Controle financeiro</span>
          </Link>
          <Link to="/" className="text-xs text-muted-foreground hover:text-foreground">
            ← Voltar
          </Link>
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
        <section className="space-y-1">
          <h1 className="font-sans text-xl font-semibold tracking-tight">Inbox</h1>
          <p className="text-sm text-muted-foreground">
            {data?.pending_count ?? 0} pendente{(data?.pending_count ?? 0) === 1 ? '' : 's'} para revisar.
          </p>
        </section>

        <div className="space-y-2">
          {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}
          {!isLoading && (data?.transactions.length ?? 0) === 0 && (
            <p className="text-sm text-muted-foreground" data-testid="inbox-empty">
              Nada pendente. Tudo revisado 🎉
            </p>
          )}
          {data?.transactions.map((t) => (
            <InboxRow key={t.id} transaction={t} />
          ))}
        </div>
      </div>
    </main>
  )
}

function InboxRow({ transaction: t }: { transaction: InboxTransaction }) {
  const consolidate = useConsolidate()
  const reject = useReject()
  const remove = useRemoveTransaction()
  const update = useUpdateTransaction()

  const [editing, setEditing] = useState(false)
  const [title, setTitle] = useState(t.improved_title ?? '')
  const [amount, setAmount] = useState((t.amount_cents / 100).toFixed(2))

  const busy =
    consolidate.isPending || reject.isPending || remove.isPending || update.isPending

  const saveEdit = async () => {
    const cents = Math.round(parseFloat(amount.replace(',', '.')) * 100)
    await update.mutateAsync({
      id: t.id,
      lock_version: t.lock_version,
      improved_title: title.trim() || undefined,
      amount_cents: Number.isFinite(cents) ? cents : undefined,
    })
    setEditing(false)
  }

  return (
    <Card data-testid={`inbox-row-${t.id}`}>
      <CardBody className="py-3 space-y-2">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="text-sm font-medium text-foreground truncate">
              {t.improved_title || t.original_description}
            </div>
            <div className="text-[11px] text-muted-foreground truncate">
              {formatDate(t.occurred_at)} · {t.account_name ?? '—'}
            </div>
          </div>
          <div
            className={`text-sm font-medium shrink-0 ${t.direction === 'credit' ? 'text-success' : 'text-foreground'}`}
          >
            {t.direction === 'debit' ? '-' : '+'}
            {formatMoney(t.amount_cents, t.currency)}
          </div>
        </div>

        {editing && (
          <div className="flex flex-wrap gap-2 items-center">
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Título"
              data-testid={`edit-title-${t.id}`}
            />
            <Input
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              inputMode="decimal"
              className="w-28"
              data-testid={`edit-amount-${t.id}`}
            />
            <Button size="sm" onClick={saveEdit} disabled={busy} data-testid={`save-${t.id}`}>
              Salvar
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setEditing(false)} disabled={busy}>
              Cancelar
            </Button>
          </div>
        )}

        {!editing && (
          <div className="flex flex-wrap gap-2">
            <Button
              size="sm"
              onClick={() => consolidate.mutate(t.id)}
              disabled={busy}
              data-testid={`accept-${t.id}`}
            >
              Aceitar
            </Button>
            <Button
              size="sm"
              variant="outline"
              onClick={() => setEditing(true)}
              disabled={busy}
              data-testid={`edit-${t.id}`}
            >
              Editar
            </Button>
            <Button
              size="sm"
              variant="outline"
              onClick={() => reject.mutate(t.id)}
              disabled={busy}
              data-testid={`reject-${t.id}`}
            >
              Rejeitar
            </Button>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => remove.mutate(t.id)}
              disabled={busy}
              data-testid={`remove-${t.id}`}
            >
              Remover
            </Button>
          </div>
        )}
      </CardBody>
    </Card>
  )
}
