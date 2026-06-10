import { useNavigate } from 'react-router'
import { Inbox, CircleAlert, Repeat, Bell, type LucideIcon } from 'lucide-react'
import { Sheet } from '../components/Sheet'
import {
  useNotifications,
  useMarkRead,
  useMarkAllRead,
  type AppNotification,
  type NotificationKind,
} from './useNotifications'

const KIND_ICON: Partial<Record<NotificationKind, LucideIcon>> = {
  inbox_new: Inbox,
  sync_failed: CircleAlert,
  recurrent_missed: Repeat,
}

const KIND_ROUTE: Partial<Record<NotificationKind, string>> = {
  inbox_new: '/inbox',
  sync_failed: '/contas',
  recurrent_missed: '/recorrentes',
}

function title(n: AppNotification): string {
  const p = n.payload
  switch (n.kind) {
    case 'inbox_new': {
      const count = Number(p.count ?? 0)
      return count === 1 ? '1 novo gasto na inbox' : `${count} novos gastos na inbox`
    }
    case 'sync_failed':
      return `Falha na sincronização do ${String(p.institution_label ?? 'banco')}`
    case 'recurrent_missed':
      return `Recorrente atrasada: ${String(p.descriptor_pattern ?? '')}`
    default:
      return 'Novo aviso'
  }
}

function description(n: AppNotification): string | null {
  const p = n.payload
  switch (n.kind) {
    case 'sync_failed':
      return p.error_message ? String(p.error_message) : null
    case 'recurrent_missed': {
      const days = Number(p.days_overdue ?? 0)
      return days === 1 ? '1 dia de atraso' : `${days} dias de atraso`
    }
    default:
      return null
  }
}

// "há 5 min", "há 3 h", "há 2 d" — granularidade grossa basta aqui.
function relativeTime(iso: string): string {
  const minutes = Math.max(0, Math.floor((Date.now() - Date.parse(iso)) / 60_000))
  if (minutes < 1) return 'agora'
  if (minutes < 60) return `há ${minutes} min`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `há ${hours} h`
  return `há ${Math.floor(hours / 24)} d`
}

/**
 * Painel do sininho (RF17): lista as notificações do workspace, marca como
 * lida ao clicar (e navega pro contexto), "Marcar todas como lidas" no topo.
 */
export function NotificationsPanel({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { data } = useNotifications()
  const markRead = useMarkRead()
  const markAllRead = useMarkAllRead()
  const navigate = useNavigate()

  const notifications = data?.notifications ?? []
  const hasUnread = (data?.unread_count ?? 0) > 0

  function onItemClick(n: AppNotification) {
    if (!n.read_at) markRead.mutate(n.id)
    onClose()
    const route = KIND_ROUTE[n.kind]
    if (route) navigate(route)
  }

  return (
    <Sheet open={open} onClose={onClose} width={400}>
      <div className="flex items-center justify-between px-5 h-14 border-b border-border">
        <h2 className="font-display text-[15px] font-semibold">Notificações</h2>
        {hasUnread && (
          <button
            onClick={() => markAllRead.mutate()}
            className="text-xs text-muted-foreground hover:text-foreground"
            data-testid="mark-all-read"
          >
            Marcar todas como lidas
          </button>
        )}
      </div>

      {notifications.length === 0 ? (
        <div className="flex flex-col items-center gap-2 py-16 text-muted-foreground">
          <Bell size={20} />
          <p className="text-sm">Nenhuma notificação</p>
        </div>
      ) : (
        <ul data-testid="notifications-list">
          {notifications.map((n) => {
            const Icon = KIND_ICON[n.kind] ?? Bell
            const desc = description(n)
            return (
              <li key={n.id} className="border-b border-border last:border-b-0">
                <button
                  onClick={() => onItemClick(n)}
                  className="w-full flex items-start gap-3 px-5 py-3 text-left hover:bg-muted"
                  data-testid="notification-item"
                >
                  <Icon size={16} className="mt-0.5 shrink-0 text-muted-foreground" />
                  <span className="min-w-0 flex-1">
                    <span className="block text-[13px] text-foreground">{title(n)}</span>
                    {desc && (
                      <span className="block text-xs text-muted-foreground truncate">{desc}</span>
                    )}
                    <span className="block text-[11px] text-muted-foreground mt-0.5">
                      {relativeTime(n.created_at)}
                    </span>
                  </span>
                  {!n.read_at && (
                    <span
                      className="mt-1.5 h-2 w-2 rounded-full bg-primary shrink-0"
                      data-testid="unread-dot"
                    />
                  )}
                </button>
              </li>
            )
          })}
        </ul>
      )}
    </Sheet>
  )
}
