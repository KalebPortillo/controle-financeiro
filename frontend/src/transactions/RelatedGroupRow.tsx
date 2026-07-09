import { Check, CheckSquare, Link2 } from 'lucide-react'
import { Money } from '../components/Money'
import { TagChip } from '../components/TagChip'
import { AccountTag } from './AccountTag'
import { AiConfidenceBadge, NotAnalyzedBadge } from './AiConfidenceBadge'
import { CurrencyChip } from './CurrencyChip'
import { SwipeableRow } from './SwipeableRow'
import type { InboxItem } from './inboxItems'
import { formatDayMonth, displayTitle } from './display'
import { satelliteSummary } from './relationType'

type RelatedGroupItem = Extract<InboxItem, { kind: 'related' }>

/**
 * Item agregado de um gasto + suas relacionadas (RF23 Fase 2): compra internacional
 * junto do IOF (ou tarifa) que ela gerou, quando ambos estão no inbox. Espelha o
 * InstallmentGroupRow (mobile-first): título da âncora + selo IA na 1ª linha, fonte
 * na 2ª, resumo das relacionadas na 3ª. Total = custo combinado. Aceitar/rejeitar/
 * selecionar age no conjunto (âncora + satélites).
 */
export function RelatedGroupRow({
  item, selected, active, onToggleGroup, onAcceptGroup, onOpenGroup,
}: {
  item: RelatedGroupItem
  selected: boolean
  active: boolean
  onToggleGroup: () => void
  onAcceptGroup: () => void
  onOpenGroup: () => void
}) {
  const { anchor, satellites, satelliteTypes, signedTotalCents, key } = item
  const title = displayTitle(anchor)
  const hasTitle = Boolean(anchor.improved_title)
  // Resumo dos satélites realmente agrupados (inclui netos-irmãos, ex.: estorno de IOF).
  const summary = satelliteSummary(satellites.flatMap((s) => (satelliteTypes.get(s.id) ? [satelliteTypes.get(s.id)!] : [])))

  return (
    <SwipeableRow
      testid={`inbox-related-${key}`}
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
            aria-label="Selecionar relacionadas"
            className="cursor-pointer accent-[var(--accent)]"
            data-testid={`select-related-${key}`}
          />
        </label>

        <div className="min-w-0">
          {/* 1ª linha: título da âncora + selo IA */}
          <div className="flex items-center gap-1.5 truncate">
            <span className={`text-[13px] font-medium truncate ${hasTitle ? '' : 'font-mono text-muted-foreground'}`}>
              {title}
            </span>
            {anchor.ai_confidence && <AiConfidenceBadge confidence={anchor.ai_confidence} />}
            {anchor.ai_status === 'failed' && <NotAnalyzedBadge id={anchor.id} />}
            <CurrencyChip currency={anchor.foreign_currency} />
          </div>
          {/* 2ª linha: fonte */}
          <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground mt-0.5">
            <AccountTag t={anchor} />
          </div>
          {/* 3ª linha: resumo das relacionadas */}
          <div className="flex items-center gap-1 text-[11px] text-muted-foreground mt-0.5">
            <Link2 size={11} className="shrink-0" />
            <span>com {summary} · {satellites.length + 1} no inbox</span>
          </div>
          {/* tags no mobile */}
          {anchor.tags.length > 0 && (
            <div className="flex md:hidden items-center gap-1.5 mt-1.5 overflow-hidden">
              {anchor.tags.slice(0, 2).map((tag) => (
                <TagChip key={tag.id} name={tag.name} color={tag.color} />
              ))}
              {anchor.tags.length > 2 && <span className="text-[11px] text-muted-foreground">+{anchor.tags.length - 2}</span>}
            </div>
          )}
        </div>

        {/* tags no desktop */}
        <div className="hidden md:flex items-center gap-1.5 overflow-hidden">
          {anchor.tags.slice(0, 2).map((tag) => (
            <TagChip key={tag.id} name={tag.name} color={tag.color} />
          ))}
          {anchor.tags.length > 2 && <span className="text-[11px] text-muted-foreground">+{anchor.tags.length - 2}</span>}
        </div>

        {/* data da compra + custo combinado */}
        <div className="text-right whitespace-nowrap">
          <div className="text-[11px] text-muted-foreground tabular-nums mb-0.5" data-testid={`related-date-${key}`}>
            {formatDayMonth(anchor.occurred_at)}
          </div>
          <span data-testid={`related-total-${key}`}>
            <Money cents={signedTotalCents} signed className="font-semibold" />
          </span>
        </div>
      </div>
    </SwipeableRow>
  )
}
