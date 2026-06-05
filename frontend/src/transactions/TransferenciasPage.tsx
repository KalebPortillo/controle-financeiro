import { ArrowRight, Repeat2 } from 'lucide-react'
import { Money } from '../components/Money'
import { Badge } from '../components/Badge'
import { Button } from '../components/Button'
import {
  useInternalTransfers,
  useUnmarkInternalTransfer,
  type InternalTransfer,
} from './useInternalTransfers'

/**
 * RF11.3 — movimentações internas: lista os pares de transferência (detectados
 * automaticamente ou marcados à mão) para reconciliação. Permite desmarcar
 * (RF11.4) — aí a saída/entrada voltam a contar como gasto/receita.
 */
export function TransferenciasPage() {
  const { data: transfers, isLoading } = useInternalTransfers()

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <section className="space-y-1">
        <div className="flex items-center gap-2">
          <Repeat2 className="size-5" />
          <h1 className="font-sans text-2xl font-semibold tracking-tight">Movimentações internas</h1>
        </div>
        <p className="text-sm text-muted-foreground">
          Transferências entre suas contas. Não contam como gasto nem receita.
        </p>
      </section>

      {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}
      {!isLoading && (transfers?.length ?? 0) === 0 && (
        <p className="text-sm text-muted-foreground" data-testid="transfers-empty">
          Nenhuma transferência interna ainda.
        </p>
      )}

      <ul className="space-y-2">
        {transfers?.map((t) => (
          <TransferRow key={t.id} transfer={t} />
        ))}
      </ul>
    </div>
  )
}

function TransferRow({ transfer: t }: { transfer: InternalTransfer }) {
  const unmark = useUnmarkInternalTransfer()
  return (
    <li
      className="border border-border rounded-lg p-4 flex items-center gap-3"
      data-testid={`transfer-${t.id}`}
    >
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 text-sm">
          <span className="truncate">{t.debit.account_name ?? '—'}</span>
          <ArrowRight size={14} className="text-muted-foreground shrink-0" />
          <span className="truncate">{t.credit.account_name ?? '—'}</span>
          <Badge variant={t.manual ? 'outline' : 'secondary'}>{t.manual ? 'manual' : 'auto'}</Badge>
        </div>
        <div className="text-xs text-muted-foreground mt-0.5">{t.debit.occurred_at}</div>
      </div>
      <Money cents={t.debit.amount_cents} />
      <Button
        variant="ghost"
        size="sm"
        onClick={() => unmark.mutate(t.id)}
        disabled={unmark.isPending}
        data-testid={`unmark-${t.id}`}
      >
        Desmarcar
      </Button>
    </li>
  )
}
