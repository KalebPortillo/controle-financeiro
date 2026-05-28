import { Link } from 'react-router'
import { useInbox } from './useInbox'

/**
 * Badge de pendentes na inbox (RF2.4). Mostra a contagem e leva pra /inbox.
 * Some quando não há nada pendente.
 */
export function InboxBadge() {
  const { data } = useInbox()
  const count = data?.pending_count ?? 0
  if (count === 0) return null

  return (
    <Link
      to="/inbox"
      className="flex items-center gap-1.5 text-xs text-foreground hover:opacity-80"
      title="Transações pendentes"
      data-testid="inbox-badge"
    >
      Inbox
      <span className="inline-flex items-center justify-center min-w-4 h-4 px-1 rounded-full bg-primary text-primary-foreground text-[10px] font-medium">
        {count}
      </span>
    </Link>
  )
}
