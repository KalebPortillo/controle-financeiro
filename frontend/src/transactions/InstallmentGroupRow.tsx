import { useState } from 'react'
import { Check, CheckSquare, ChevronRight, ChevronDown, Layers } from 'lucide-react'
import { Money } from '../components/Money'
import { TagChip } from '../components/TagChip'
import { AccountTag } from './AccountTag'
import { InstallmentBadge } from './InstallmentBadge'
import { SwipeableRow } from './SwipeableRow'
import type { InboxTransaction } from './useInbox'
import type { InboxItem } from './inboxItems'

type InstallmentItem = Extract<InboxItem, { kind: 'installment' }>

function formatDate(iso: string): string {
  const [, m, d] = iso.split('-')
  return `${d}/${m}`
}

function signed(direction: string, cents: number): number {
  return direction === 'debit' ? -cents : cents
}

/**
 * Item agregado de um parcelamento no inbox (RF9.4): cabeçalho com título, fonte,
 * "parcelado · Nx" e o VALOR TOTAL (soma das parcelas presentes). Expande numa
 * sub-lista das parcelas (3/12 · valor · mês). Aceitar/selecionar age sobre o
 * grupo inteiro; clicar abre o detalhe (da parcela representativa / da parcela
 * clicada na sub-lista).
 */
export function InstallmentGroupRow({
  item, selected, active, onToggleGroup, onAcceptGroup, onOpenParcel,
}: {
  item: InstallmentItem
  selected: boolean
  active: boolean
  onToggleGroup: () => void
  onAcceptGroup: () => void
  onOpenParcel: (t: InboxTransaction) => void
}) {
  const [expanded, setExpanded] = useState(false)
  const { representative: rep, parcels, total, groupId } = item
  const title = rep.improved_title || rep.original_description

  return (
    <div className="border-b border-border last:border-b-0">
      <SwipeableRow
        testid={`inbox-group-${groupId}`}
        swipeLeft={{
          onAction: onAcceptGroup,
          label: 'Aceitar',
          icon: <Check size={16} />,
          idleClass: 'bg-success/30 text-success',
          armedClass: 'bg-[var(--success-vivid)] text-white',
        }}
        swipeRight={{
          onAction: onToggleGroup,
          label: selected ? 'Desmarcar' : 'Selecionar',
          icon: <CheckSquare size={16} />,
          idleClass: 'bg-accent/30 text-accent',
          armedClass: 'bg-accent text-accent-foreground',
        }}
        onClick={() => onOpenParcel(rep)}
      >
        <div
          className={`grid grid-cols-[28px_1fr_auto] md:grid-cols-[32px_1fr_150px_140px] gap-3 items-center px-4 py-3 transition-colors hover:bg-muted ${
            active ? 'bg-muted shadow-[inset_2px_0_0_0_var(--accent)]' : ''
          } ${selected ? 'bg-[color-mix(in_srgb,var(--accent)_6%,transparent)]' : ''}`}
        >
          <label
            className="flex items-center"
            onClick={(e) => e.stopPropagation()}
            onPointerDown={(e) => e.stopPropagation()}
          >
            <input
              type="checkbox"
              checked={selected}
              onChange={onToggleGroup}
              aria-label="Selecionar parcelamento"
              className="cursor-pointer accent-[var(--accent)]"
              data-testid={`select-group-${groupId}`}
            />
          </label>

          <div className="min-w-0">
            <div className="flex items-center gap-1.5 truncate">
              <span className="text-[13px] font-medium truncate">{title}</span>
              <span className="inline-flex items-center gap-1 rounded-sm border border-border px-1 py-0 text-[10px] font-medium text-muted-foreground">
                <Layers size={10} /> parcelado · {rep.installment_total}x
              </span>
            </div>
            <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground mt-0.5">
              <AccountTag kind={rep.account_kind} institutionLabel={rep.institution_label} accountName={rep.account_name} />
              <span className="text-border">·</span>
              <span>{parcels.length} {parcels.length === 1 ? 'parcela' : 'parcelas'} no inbox</span>
            </div>
          </div>

          <div className="hidden md:flex items-center gap-1.5 overflow-hidden">
            {rep.tags.slice(0, 2).map((tag) => (
              <TagChip key={tag.id} name={tag.name} color={tag.color} />
            ))}
            {rep.tags.length > 2 && <span className="text-[11px] text-muted-foreground">+{rep.tags.length - 2}</span>}
          </div>

          <div className="flex items-center justify-end gap-2 whitespace-nowrap">
            <span data-testid={`group-total-${groupId}`}>
              <Money cents={signed(rep.direction, total)} signed className="font-semibold" />
            </span>
            {parcels.length > 1 && (
              <button
                type="button"
                aria-label={expanded ? 'Recolher parcelas' : 'Ver parcelas'}
                data-testid={`expand-group-${groupId}`}
                onClick={(e) => { e.stopPropagation(); setExpanded((v) => !v) }}
                onPointerDown={(e) => e.stopPropagation()}
                className="h-6 w-6 inline-flex items-center justify-center rounded text-muted-foreground hover:bg-muted hover:text-foreground"
              >
                {expanded ? <ChevronDown size={15} /> : <ChevronRight size={15} />}
              </button>
            )}
          </div>
        </div>
      </SwipeableRow>

      {expanded && (
        <ul className="bg-muted/30 border-t border-border" data-testid={`group-parcels-${groupId}`}>
          {parcels.map((p) => (
            <li key={p.id} className="border-b border-border/60 last:border-b-0">
              <button
                type="button"
                onClick={() => onOpenParcel(p)}
                className="w-full grid grid-cols-[1fr_auto] gap-3 items-center pl-10 pr-4 py-2 text-left hover:bg-muted"
                data-testid={`parcel-${p.id}`}
              >
                <span className="flex items-center gap-1.5 text-[12px] text-muted-foreground">
                  <InstallmentBadge number={p.installment_number} total={p.installment_total} />
                  <span className="text-border">·</span>
                  <span>{formatDate(p.occurred_at)}</span>
                </span>
                <Money cents={signed(p.direction, p.amount_cents)} signed className="text-[13px]" />
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
