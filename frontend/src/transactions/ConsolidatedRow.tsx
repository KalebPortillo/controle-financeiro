import { Money } from '../components/Money'
import { TagChip } from '../components/TagChip'
import { AccountTag } from './AccountTag'
import { InstallmentBadge } from './InstallmentBadge'
import { CurrencyChip } from './CurrencyChip'
import { originalToShow, type InboxTransaction } from './useInbox'
import { formatDayMonth, signedCents, displayTitle } from './display'

/**
 * Linha de um gasto avulso no consolidado (RF4). Reusada por Gastos e pelas
 * páginas de detalhe de relatório (drill-down RF13.8).
 */
export function ConsolidatedRow({ t, onOpen }: { t: InboxTransaction; onOpen: () => void }) {
  return (
    <button
      onClick={onOpen}
      data-testid={`gasto-row-${t.id}`}
      className="grid w-full text-left grid-cols-[1fr_auto] md:grid-cols-[1fr_150px_110px] gap-3 items-center px-4 py-3 border-b border-border last:border-b-0 hover:bg-muted transition-colors"
    >
      <div className="min-w-0">
        <div className="flex items-center gap-1.5 truncate">
          <span className="text-[13px] font-medium truncate">{displayTitle(t)}</span>
          <CurrencyChip currency={t.foreign_currency} />
        </div>
        <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground mt-0.5">
          <AccountTag t={t} />
          {t.installment_total && (
            <>
              <span className="text-border">·</span>
              <InstallmentBadge number={t.installment_number} total={t.installment_total} />
            </>
          )}
        </div>
        {originalToShow(t) && (
          <div className="text-[11px] text-muted-foreground/70 font-mono truncate mt-0.5" data-testid={`original-${t.id}`}>
            orig.: {originalToShow(t)}
          </div>
        )}
        {t.tags.length > 0 && (
          <div className="flex md:hidden items-center gap-1.5 mt-1.5 overflow-hidden">
            {t.tags.slice(0, 2).map((tag) => (
              <TagChip key={tag.id} name={tag.name} color={tag.color} />
            ))}
            {t.tags.length > 2 && <span className="text-[11px] text-muted-foreground">+{t.tags.length - 2}</span>}
          </div>
        )}
      </div>
      <div className="hidden md:flex items-center gap-1.5 overflow-hidden">
        {t.tags.slice(0, 2).map((tag) => (
          <TagChip key={tag.id} name={tag.name} color={tag.color} />
        ))}
        {t.tags.length > 2 && <span className="text-[11px] text-muted-foreground">+{t.tags.length - 2}</span>}
      </div>
      <div className="text-right whitespace-nowrap">
        <div className="text-[11px] text-muted-foreground tabular-nums mb-0.5" data-testid={`date-${t.id}`}>
          {formatDayMonth(t.occurred_at)}
        </div>
        <Money cents={signedCents(t)} signed className="font-semibold" />
      </div>
    </button>
  )
}
