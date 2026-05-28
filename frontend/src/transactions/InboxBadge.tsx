import { Link } from 'react-router'
import { useInbox } from './useInbox'

/**
 * Badge de pendentes na inbox (RF2.4). Some quando não há nada pendente.
 * - variant="link" (default): chip clicável "Inbox N" — uso avulso.
 * - variant="count": só o número, sem link — usado dentro do item de nav.
 */
export function InboxBadge({ variant = 'link' }: { variant?: 'link' | 'count' }) {
  const { data } = useInbox()
  const count = data?.pending_count ?? 0
  if (count === 0) return null

  const pill = (
    <span className="inline-flex items-center justify-center min-w-4 h-4 px-1 rounded-full bg-primary text-primary-foreground text-[10px] font-medium">
      {count}
    </span>
  )

  if (variant === 'count') {
    return <span data-testid="inbox-badge-count">{pill}</span>
  }

  return (
    <Link
      to="/inbox"
      className="flex items-center gap-1.5 text-xs text-foreground hover:opacity-80"
      title="Transações pendentes"
      data-testid="inbox-badge"
    >
      Inbox
      {pill}
    </Link>
  )
}
