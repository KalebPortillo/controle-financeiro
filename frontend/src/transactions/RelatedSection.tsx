import { Link2, X } from 'lucide-react'
import { Money } from '../components/Money'
import { useOverlay } from '../app/useOverlay'
import { useUnlinkTransaction } from './useTransactionLinks'
import { RELATION_LABEL } from './relationType'
import type { InboxTransaction } from './useInbox'

/**
 * RF23 — transações relacionadas no detalhe: os satélites de um gasto (IOF,
 * tarifa…) ou o gasto de origem quando esta é o satélite. Cada item navega pra
 * transação vinculada (?tx) e pode ser desvinculado.
 */
export function RelatedSection({ transaction: t }: { transaction: InboxTransaction }) {
  const { push } = useOverlay()
  const unlink = useUnlinkTransaction()
  if (!t.related || t.related.length === 0) return null

  return (
    <div className="mt-2 pt-3.5 border-t border-border space-y-1.5" data-testid="related-section">
      <p className="text-xs text-muted-foreground">Relacionadas</p>
      {t.related.map((item) => (
        <div key={item.link_id} className="flex items-center justify-between gap-2">
          <button
            type="button"
            onClick={() => push((p) => p.set('tx', item.transaction_id))}
            data-testid={`related-${item.transaction_id}`}
            className="flex items-center gap-1.5 text-sm text-foreground hover:underline min-w-0"
          >
            <Link2 size={13} className="text-muted-foreground shrink-0" />
            <span className="truncate">
              {item.role === 'origin' ? `Origem · ${item.title}` : RELATION_LABEL[item.relation_type]}
            </span>
            <Money cents={item.amount_cents} className="text-sm shrink-0" />
          </button>
          <button
            type="button"
            onClick={() => unlink.mutate(item.link_id)}
            disabled={unlink.isPending}
            aria-label="Desvincular"
            data-testid={`related-unlink-${item.link_id}`}
            className="h-6 w-6 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground disabled:opacity-50 shrink-0"
          >
            <X size={13} />
          </button>
        </div>
      ))}
    </div>
  )
}
