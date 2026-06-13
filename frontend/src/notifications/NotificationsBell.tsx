import { Bell } from 'lucide-react'
import { useOverlay } from '../app/useOverlay'
import { useNotifications } from './useNotifications'
import { NotificationsPanel } from './NotificationsPanel'

/**
 * Sininho do header (RF17): badge com contagem de não lidas, clique abre o
 * painel. O painel é estado de URL (?notifs) pra que o back do navegador o feche
 * em vez de navegar a rota por baixo.
 */
export function NotificationsBell() {
  const { get, push, close } = useOverlay()
  const { data } = useNotifications()
  const unread = data?.unread_count ?? 0
  const open = get('notifs') != null

  return (
    <>
      <button
        aria-label="Notificações"
        data-testid="notifications-bell"
        onClick={() => push((p) => p.set('notifs', '1'))}
        className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground relative"
      >
        <Bell size={16} />
        {unread > 0 && (
          <span
            data-testid="notifications-badge"
            className="absolute -top-0.5 -right-0.5 inline-flex items-center justify-center min-w-4 h-4 px-1 rounded-full bg-primary text-primary-foreground text-[10px] font-medium"
          >
            {unread}
          </span>
        )}
      </button>
      <NotificationsPanel open={open} onClose={() => close('notifs')} />
    </>
  )
}
