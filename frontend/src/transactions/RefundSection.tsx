import { useState } from 'react'
import { Undo2 } from 'lucide-react'
import { Button } from '../components/Button'
import { Money } from '../components/Money'
import { useRefundCandidates, useLinkRefund, useUnlinkRefund } from './useRefunds'
import type { InboxTransaction } from './useInbox'

/**
 * RF10 — seção de estorno no detalhe da transação.
 * - credit: botão "Esta transação é um estorno?" → lista candidatos → vincular.
 * - debit estornado: mostra valor efetivo + nota e permite desfazer.
 */
export function RefundSection({ transaction: t }: { transaction: InboxTransaction }) {
  if (t.direction === 'credit') return <CreditRefundLinker credit={t} />
  if (t.refund) return <DebitRefundSummary transaction={t} />
  return null
}

function CreditRefundLinker({ credit }: { credit: InboxTransaction }) {
  const [open, setOpen] = useState(false)
  const { data: candidates, isLoading } = useRefundCandidates(credit.id, open)
  const link = useLinkRefund()

  // Se este crédito já é um estorno (vinculado), não oferece de novo.
  return (
    <div className="mt-2 pt-3.5 border-t border-border space-y-2" data-testid="refund-section">
      {!open && (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="inline-flex items-center gap-1.5 text-sm text-foreground hover:underline"
          data-testid="refund-open"
        >
          <Undo2 size={13} /> Esta transação é um estorno?
        </button>
      )}

      {open && (
        <div className="space-y-2">
          <p className="text-xs text-muted-foreground">Vincular a qual gasto?</p>
          {isLoading && <p className="text-xs text-muted-foreground">Buscando…</p>}
          {!isLoading && (candidates?.length ?? 0) === 0 && (
            <p className="text-xs text-muted-foreground" data-testid="refund-no-candidates">
              Nenhum gasto compatível encontrado.
            </p>
          )}
          <ul className="space-y-1.5">
            {candidates?.map((d) => (
              <li key={d.id}>
                <button
                  type="button"
                  onClick={() => link.mutate({ creditId: credit.id, refundedTransactionId: d.id })}
                  disabled={link.isPending}
                  data-testid={`refund-candidate-${d.id}`}
                  className="w-full flex items-center justify-between gap-2 rounded-md border border-border px-3 py-2 text-left hover:bg-muted disabled:opacity-50"
                >
                  <span className="text-sm truncate">{d.improved_title || d.original_description}</span>
                  <Money cents={d.amount_cents} className="text-sm shrink-0" />
                </button>
              </li>
            ))}
          </ul>
          <button
            type="button"
            onClick={() => setOpen(false)}
            className="text-xs text-muted-foreground hover:text-foreground underline"
          >
            Cancelar
          </button>
        </div>
      )}
    </div>
  )
}

function DebitRefundSummary({ transaction: t }: { transaction: InboxTransaction }) {
  const unlink = useUnlinkRefund()
  const refund = t.refund!

  return (
    <div className="mt-2 pt-3.5 border-t border-border space-y-1.5" data-testid="refund-summary">
      <div className="flex items-center gap-1.5 text-sm">
        <Undo2 size={13} className="text-accent" />
        <span>
          Estornado <Money cents={refund.refunded_amount_cents} className="text-sm" /> · efetivo{' '}
          <Money cents={t.effective_amount_cents} className="text-sm font-medium" />
        </span>
      </div>
      <Button
        variant="ghost"
        size="sm"
        onClick={() => unlink.mutate(refund.refunds[0].id)}
        disabled={unlink.isPending || refund.refunds.length === 0}
        data-testid="refund-unlink"
      >
        Desfazer estorno
      </Button>
    </div>
  )
}
