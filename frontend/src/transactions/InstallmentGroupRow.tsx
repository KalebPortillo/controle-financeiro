import { Check, CheckSquare, Layers } from 'lucide-react'
import { Money } from '../components/Money'
import { TagChip } from '../components/TagChip'
import { AccountTag } from './AccountTag'
import { AiConfidenceBadge, NotAnalyzedBadge } from './AiConfidenceBadge'
import { SwipeableRow } from './SwipeableRow'
import type { InboxItem } from './inboxItems'

type InstallmentItem = Extract<InboxItem, { kind: 'installment' }>

function signed(direction: string, cents: number): number {
  return direction === 'debit' ? -cents : cents
}

/**
 * Item agregado de um parcelamento no inbox (RF9.4). Mobile-first: linha enxuta —
 * título + selo de IA na 1ª linha, fonte na 2ª, e o indicador de parcelamento em
 * LINHA PRÓPRIA na 3ª (não disputa o título). Clicar abre o sheet do
 * parcelamento (total + lista das parcelas). Aceitar/selecionar age no grupo.
 */
export function InstallmentGroupRow({
  item, selected, active, onToggleGroup, onAcceptGroup, onOpenGroup,
}: {
  item: InstallmentItem
  selected: boolean
  active: boolean
  onToggleGroup: () => void
  onAcceptGroup: () => void
  onOpenGroup: () => void
}) {
  const { representative: rep, parcels, total, groupId } = item
  const title = rep.improved_title || rep.original_description
  const hasTitle = Boolean(rep.improved_title)

  return (
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
      onClick={onOpenGroup}
    >
      <div
        className={`grid grid-cols-[28px_1fr_auto] md:grid-cols-[32px_1fr_150px_110px] gap-3 items-center px-4 py-3 transition-colors hover:bg-muted ${
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
          {/* 1ª linha: título + selo IA */}
          <div className="flex items-center gap-1.5 truncate">
            <span className={`text-[13px] font-medium truncate ${hasTitle ? '' : 'font-mono text-muted-foreground'}`}>
              {title}
            </span>
            {rep.ai_confidence && <AiConfidenceBadge confidence={rep.ai_confidence} />}
            {rep.ai_status === 'failed' && <NotAnalyzedBadge id={rep.id} />}
          </div>
          {/* 2ª linha: fonte */}
          <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground mt-0.5">
            <AccountTag t={rep} />
          </div>
          {/* 3ª linha: indicador de parcelamento (linha própria) */}
          <div className="flex items-center gap-1 text-[11px] text-muted-foreground mt-0.5">
            <Layers size={11} className="shrink-0" />
            <span>parcelado {rep.installment_total}x · {parcels.length} no inbox</span>
          </div>
          {/* tags no mobile */}
          {rep.tags.length > 0 && (
            <div className="flex md:hidden items-center gap-1.5 mt-1.5 overflow-hidden">
              {rep.tags.slice(0, 2).map((tag) => (
                <TagChip key={tag.id} name={tag.name} color={tag.color} />
              ))}
              {rep.tags.length > 2 && <span className="text-[11px] text-muted-foreground">+{rep.tags.length - 2}</span>}
            </div>
          )}
        </div>

        {/* tags no desktop */}
        <div className="hidden md:flex items-center gap-1.5 overflow-hidden">
          {rep.tags.slice(0, 2).map((tag) => (
            <TagChip key={tag.id} name={tag.name} color={tag.color} />
          ))}
          {rep.tags.length > 2 && <span className="text-[11px] text-muted-foreground">+{rep.tags.length - 2}</span>}
        </div>

        {/* total das parcelas presentes */}
        <div className="text-right whitespace-nowrap">
          <span data-testid={`group-total-${groupId}`}>
            <Money cents={signed(rep.direction, total)} signed className="font-semibold" />
          </span>
        </div>
      </div>
    </SwipeableRow>
  )
}
