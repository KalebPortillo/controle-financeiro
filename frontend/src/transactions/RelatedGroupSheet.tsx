import { X, Link2, Check, ChevronRight } from 'lucide-react'
import { Sheet } from '../components/Sheet'
import { Button } from '../components/Button'
import { Money } from '../components/Money'
import { AccountTag } from './AccountTag'
import type { InboxItem } from './inboxItems'
import type { InboxTransaction } from './useInbox'
import { formatDayMonth, displayTitle, signedCents } from './display'
import { RELATION_LABEL, satelliteSummary } from './relationType'

type RelatedGroupItem = Extract<InboxItem, { kind: 'related' }>

const STATUS_LABEL: Record<string, string> = {
  pending: 'pendente', consolidated: 'consolidado', rejected: 'rejeitado', split: 'dividido',
}

/**
 * Detalhe de um gasto + suas relacionadas (RF23 Fase 2) — abre ao clicar no item
 * agregado do inbox. Mobile-first: Sheet de tela cheia com o custo combinado, a
 * ORIGEM em destaque e a lista das relacionadas (IOF/tarifa…). Cada item abre seu
 * detalhe. Rodapé aceita/rejeita o conjunto todo de uma vez.
 */
export function RelatedGroupSheet({
  item, open, onClose, onOpenMember, onAcceptGroup, onRejectGroup,
}: {
  item: RelatedGroupItem | null
  open: boolean
  onClose: () => void
  onOpenMember: (t: InboxTransaction) => void
  onAcceptGroup: () => void
  onRejectGroup: () => void
}) {
  return (
    <Sheet open={open} onClose={onClose} width={460}>
      {item && (
        <Inner
          key={item.key}
          item={item}
          onClose={onClose}
          onOpenMember={onOpenMember}
          onAcceptGroup={onAcceptGroup}
          onRejectGroup={onRejectGroup}
        />
      )}
    </Sheet>
  )
}

function Inner({
  item, onClose, onOpenMember, onAcceptGroup, onRejectGroup,
}: {
  item: RelatedGroupItem
  onClose: () => void
  onOpenMember: (t: InboxTransaction) => void
  onAcceptGroup: () => void
  onRejectGroup: () => void
}) {
  const { anchor, satellites, signedTotalCents, key } = item
  // Tipo de cada satélite, lido dos vínculos da âncora (role satellite).
  const typeById = new Map(
    (anchor.related ?? []).filter((r) => r.role === 'satellite').map((r) => [r.transaction_id, r.relation_type]),
  )
  // Só os satélites realmente no grupo (estorno pode entrar sem IOF presente).
  const summary = satelliteSummary(satellites.flatMap((s) => (typeById.get(s.id) ? [typeById.get(s.id)!] : [])))

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-5 pt-5 pb-4 border-b border-border">
        <div className="flex items-start gap-2.5">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5 mb-1">
              <Link2 size={13} className="text-muted-foreground shrink-0" />
              <span className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground">
                Gasto + {summary}
              </span>
            </div>
            <div className="font-display text-lg font-semibold tracking-tight truncate">
              {displayTitle(anchor)}
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
        <div className="mt-3 flex items-baseline gap-2">
          <Money cents={signedTotalCents} signed className="text-3xl font-medium" />
          <span className="text-xs text-muted-foreground">custo total</span>
        </div>
        <div className="mt-2">
          <AccountTag t={anchor} />
        </div>
      </div>

      {/* Body — origem + relacionadas */}
      <div className="flex-1 overflow-y-auto px-5 py-5 flex flex-col gap-3.5">
        <FieldLabel>Itens ({item.members.length})</FieldLabel>
        <ul className="border border-border rounded-md overflow-hidden" data-testid={`related-sheet-members-${key}`}>
          <MemberRow t={anchor} badge="Origem" onOpen={() => onOpenMember(anchor)} />
          {satellites.map((s) => (
            <MemberRow
              key={s.id}
              t={s}
              badge={RELATION_LABEL[typeById.get(s.id) ?? 'iof']}
              onOpen={() => onOpenMember(s)}
            />
          ))}
        </ul>
      </div>

      {/* Rodapé — aceitar/rejeitar o conjunto */}
      <div className="px-5 py-4 border-t border-border flex gap-2">
        <Button
          variant="ghost"
          onClick={() => { onRejectGroup(); onClose() }}
          data-testid={`related-sheet-reject-${key}`}
        >
          Rejeitar todas
        </Button>
        <Button
          variant="primary"
          className="flex-1"
          onClick={() => { onAcceptGroup(); onClose() }}
          data-testid={`related-sheet-accept-${key}`}
        >
          <Check size={16} /> Aceitar todas ({item.members.length})
        </Button>
      </div>
    </div>
  )
}

function MemberRow({ t, badge, onOpen }: { t: InboxTransaction; badge: string; onOpen: () => void }) {
  return (
    <li className="border-b border-border last:border-b-0">
      <button
        type="button"
        onClick={onOpen}
        className="w-full grid grid-cols-[auto_1fr_auto_auto] gap-2 items-center px-3 py-2.5 text-left hover:bg-muted"
        data-testid={`related-sheet-member-${t.id}`}
      >
        <span className="inline-flex items-center h-5 px-1.5 rounded bg-muted text-[10px] uppercase tracking-wider font-medium text-muted-foreground shrink-0">
          {badge}
        </span>
        <span className="min-w-0">
          <span className="block text-[12px] text-foreground truncate">{displayTitle(t)}</span>
          <span className="block text-[11px] text-muted-foreground truncate">
            {formatDayMonth(t.occurred_at)} · {STATUS_LABEL[t.status] ?? t.status}
          </span>
        </span>
        <Money cents={signedCents(t)} signed className="text-[13px]" />
        <ChevronRight size={14} className="text-muted-foreground" />
      </button>
    </li>
  )
}

function FieldLabel({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-1.5 text-[11px] uppercase tracking-wider font-medium text-muted-foreground">
      <span>{children}</span>
    </div>
  )
}
