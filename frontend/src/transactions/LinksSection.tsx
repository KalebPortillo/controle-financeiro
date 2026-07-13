import { useState } from 'react'
import { Link2, Search, Undo2 } from 'lucide-react'
import { Money } from '../components/Money'
import { useOverlay } from '../app/useOverlay'
import { useDebounced } from '../app/useDebounced'
import { useLinkCandidates, useLinkTransaction, useUnlinkTransaction } from './useTransactionLinks'
import { useRefundCandidates, useLinkRefund, useUnlinkRefund } from './useRefunds'
import { RELATION_LABEL } from './relationType'
import { displayTitle, formatDayMonth } from './display'
import type { InboxTransaction, RelatedItem } from './useInbox'

/**
 * Vínculos (RF10 + RF23) — seção única do detalhe que relaciona esta transação a
 * outra. Estorno é só mais um TIPO de vínculo ("Estorno"): a lista mostra IOF,
 * tarifa, juros, ajuste E estornos juntos, e o picker oferece o chip Estorno.
 * Por baixo cada tipo roteia pro seu endpoint (link_kind 'refund' → estorno;
 * 'link' → RF23), sem o usuário perceber a diferença.
 */
export function LinksSection({ transaction: t }: { transaction: InboxTransaction }) {
  const related = t.related ?? []

  return (
    <div className="mt-2 pt-3.5 border-t border-border space-y-2" data-testid="links-section">
      {t.refund && <EffectiveSummary transaction={t} />}
      {related.length > 0 && <RelatedList items={related} />}
      {/* O botão de vincular fica SEMPRE disponível — uma transação pode acumular
          vários vínculos (IOF, tarifa, estornos…) e sempre dá pra adicionar mais. */}
      <LinkPicker transaction={t} />
    </div>
  )
}

// Débito estornado: quanto foi estornado e o valor efetivo (RF10). Só informativo
// — o desfazer fica em cada item da lista.
function EffectiveSummary({ transaction: t }: { transaction: InboxTransaction }) {
  const refund = t.refund!
  return (
    <div className="flex items-center gap-1.5 text-sm" data-testid="refund-effective">
      <Undo2 size={13} className="text-accent" />
      <span>
        Estornado <Money cents={refund.refunded_amount_cents} className="text-sm" /> · efetivo{' '}
        <Money cents={t.effective_amount_cents} className="text-sm font-medium" />
      </span>
    </div>
  )
}

function RelatedList({ items }: { items: RelatedItem[] }) {
  const { push } = useOverlay()
  const unlinkLink = useUnlinkTransaction()
  const unlinkRefund = useUnlinkRefund()
  const busy = unlinkLink.isPending || unlinkRefund.isPending

  const unlink = (item: RelatedItem) =>
    item.link_kind === 'refund' ? unlinkRefund.mutate(item.link_id) : unlinkLink.mutate(item.link_id)

  return (
    <div className="space-y-1.5">
      <p className="text-xs text-muted-foreground">Vínculos</p>
      {items.map((item) => (
        <div key={item.link_id} data-testid={`link-item-${item.link_id}`} className="space-y-0.5">
          <div className="flex items-center justify-between gap-2">
            <button
              type="button"
              onClick={() => push((p) => p.set('tx', item.transaction_id))}
              data-testid={`link-open-${item.transaction_id}`}
              className="flex items-center gap-1.5 text-sm text-foreground hover:underline min-w-0"
            >
              {item.relation_type === 'refund' ? (
                <Undo2 size={13} className="text-accent shrink-0" />
              ) : (
                <Link2 size={13} className="text-muted-foreground shrink-0" />
              )}
              <span className="truncate">{itemLabel(item)}</span>
              <Money cents={item.amount_cents} className="text-sm shrink-0" />
            </button>
            <button
              type="button"
              onClick={() => unlink(item)}
              disabled={busy}
              aria-label="Desvincular"
              data-testid={`link-unlink-${item.link_id}`}
              className="h-6 w-6 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground disabled:opacity-50 shrink-0"
            >
              <Undo2 size={13} />
            </button>
          </div>
          {item.relation_type === 'refund' && item.origin === 'automatic' && (
            <p className="text-xs text-muted-foreground pl-[18px]" data-testid={`link-auto-badge-${item.link_id}`}>
              {autoLinkLabel(item.confidence === 'medium')}
            </p>
          )}
        </div>
      ))}
    </div>
  )
}

// Rótulo do item: origem prefixa "Estorno de …" (estorno) / "Origem · …" (RF23);
// satélite usa o rótulo do tipo (Estorno, IOF, Tarifa…).
function itemLabel(item: RelatedItem): string {
  if (item.role === 'origin') {
    return item.relation_type === 'refund' ? `Estorno de ${item.title}` : `Origem · ${item.title}`
  }
  return RELATION_LABEL[item.relation_type]
}

// RF23 F3 + RF10 — vincular esta transação a outra. "Estorno" é o primeiro tipo:
// num crédito, marca ESTE crédito como estorno de um gasto; num débito, marca um
// crédito como estorno DESTE gasto (débitos também escolhem IOF/tarifa/juros/ajuste,
// que vinculam a um gasto de origem).
function LinkPicker({ transaction: t }: { transaction: InboxTransaction }) {
  const isCredit = t.direction === 'credit'
  const [open, setOpen] = useState(false)
  const [type, setType] = useState<RelatedItem['relation_type']>('refund')
  const [q, setQ] = useState('')
  const debouncedQ = useDebounced(q, 250)

  const isRefundFlow = type === 'refund'
  const refundCandidates = useRefundCandidates(t.id, open && isRefundFlow)
  const linkCandidates = useLinkCandidates(t.id, debouncedQ, open && !isRefundFlow)
  const linkRefund = useLinkRefund()
  const linkTransaction = useLinkTransaction()

  const candidates = isRefundFlow ? refundCandidates.data : linkCandidates.data
  const loading = isRefundFlow ? refundCandidates.isLoading : linkCandidates.isLoading
  const busy = linkRefund.isPending || linkTransaction.isPending

  // "Estorno" sempre primeiro. Crédito só pode ser estorno; débito também vincula
  // satélites (IOF/tarifa/juros/ajuste).
  const chipTypes: RelatedItem['relation_type'][] = isCredit
    ? ['refund']
    : ['refund', 'iof', 'fee', 'interest', 'adjustment']

  const pick = (candidateId: string) => {
    const onSuccess = () => setOpen(false)
    if (isRefundFlow) {
      // Crédito atual → escolhe o gasto estornado. Débito atual → o candidato é o
      // crédito, e este gasto é o refunded. link_refund sempre tem o crédito como :id.
      const args = isCredit
        ? { creditId: t.id, refundedTransactionId: candidateId }
        : { creditId: candidateId, refundedTransactionId: t.id }
      linkRefund.mutate(args, { onSuccess })
    } else {
      linkTransaction.mutate({ id: t.id, origin_id: candidateId, relation_type: type }, { onSuccess })
    }
  }

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="inline-flex items-center gap-1.5 text-sm text-foreground hover:underline"
        data-testid="link-open"
      >
        {isCredit ? <Undo2 size={13} /> : <Link2 size={13} />}
        {isCredit ? 'Esta transação é um estorno?' : 'Vincular a outra transação'}
      </button>
    )
  }

  const prompt = isRefundFlow
    ? isCredit
      ? 'Estorno de qual gasto?'
      : 'Estornado por qual crédito?'
    : 'Vincular a qual gasto?'

  return (
    <div className="space-y-2.5" data-testid="link-picker">
      {chipTypes.length > 1 && (
        <div className="flex items-center gap-1.5">
          {chipTypes.map((rt) => (
            <button
              key={rt}
              type="button"
              onClick={() => setType(rt)}
              data-testid={`link-type-${rt}`}
              className={`h-7 px-2.5 rounded-md border text-xs transition-colors ${
                type === rt
                  ? 'border-accent bg-accent/10 text-accent'
                  : 'border-border text-muted-foreground hover:bg-muted'
              }`}
            >
              {RELATION_LABEL[rt]}
            </button>
          ))}
        </div>
      )}

      <p className="text-xs text-muted-foreground">{prompt}</p>

      {!isRefundFlow && (
        <div className="relative flex items-center">
          <Search size={13} className="absolute left-2.5 text-muted-foreground pointer-events-none" />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar o gasto de origem…"
            data-testid="link-search"
            aria-label="Buscar gasto de origem"
            className="h-8 w-full rounded-md border border-input bg-background pl-8 pr-2 text-sm text-foreground placeholder:text-muted-foreground focus:border-ring focus:outline-2 focus:outline-ring/30"
          />
        </div>
      )}

      {loading && <p className="text-xs text-muted-foreground">Buscando…</p>}
      {!loading && (candidates?.length ?? 0) === 0 && (
        <p className="text-xs text-muted-foreground" data-testid="link-empty">
          Nenhum gasto compatível encontrado.
        </p>
      )}
      <ul className="space-y-1.5 max-h-56 overflow-y-auto">
        {candidates?.map((c) => (
          <li key={c.id}>
            <button
              type="button"
              onClick={() => pick(c.id)}
              disabled={busy}
              data-testid={`link-candidate-${c.id}`}
              className="w-full flex items-center justify-between gap-2 rounded-md border border-border px-3 py-2 text-left hover:bg-muted disabled:opacity-50"
            >
              <span className="min-w-0">
                <span className="block text-sm truncate">{displayTitle(c)}</span>
                <span className="block text-[11px] text-muted-foreground tabular-nums">
                  {formatDayMonth(c.occurred_at)}
                </span>
              </span>
              <Money cents={c.amount_cents} className="text-sm shrink-0" />
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
  )
}

// Texto do selo de auto-vínculo (RF10.6): média confiança pede conferência.
function autoLinkLabel(isMedium: boolean): string {
  return isMedium
    ? 'Vinculado automaticamente (confiança média — confira)'
    : 'Vinculado automaticamente pelo estorno'
}
