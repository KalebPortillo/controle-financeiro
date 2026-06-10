import { NavLink, useLocation, useNavigate, Outlet } from 'react-router'
import {
  Inbox,
  Wallet,
  PieChart,
  BarChart3,
  Repeat,
  MoreHorizontal,
  Search,
  Sun,
  Moon,
  type LucideIcon,
} from 'lucide-react'
import { WalletLogo } from '../components/WalletLogo'
import { useTheme } from '../components/useTheme'
import { useSession } from '../auth/useSession'
import { InboxBadge } from '../transactions/InboxBadge'
import { GlobalSyncIndicator } from '../bank/GlobalSyncIndicator'
import { NotificationsBell } from '../notifications/NotificationsBell'
import { useNotificationsChannel } from '../notifications/useNotificationsChannel'

type NavItem = {
  id: string
  label: string
  Icon: LucideIcon
  to?: string // ausente = "em breve" (desabilitado)
}

const NAV_ITEMS: NavItem[] = [
  { id: 'inbox', label: 'Inbox', Icon: Inbox, to: '/inbox' },
  { id: 'gastos', label: 'Gastos', Icon: Wallet, to: '/gastos' },
  { id: 'orcamentos', label: 'Orçamentos', Icon: PieChart },
  { id: 'recorrentes', label: 'Recorrentes', Icon: Repeat, to: '/recorrentes' },
  { id: 'relatorios', label: 'Relatórios', Icon: BarChart3, to: '/relatorios' },
  { id: 'mais', label: 'Mais', Icon: MoreHorizontal, to: '/mais' },
]

/**
 * App shell (RF15): sidebar no desktop, bottom nav no mobile, top bar com busca
 * (placeholder), toggle de tema e notificações. Recriado do design system
 * (ui_kits/app/Shell.jsx). As telas vivem no <Outlet/>.
 */
export function AppLayout() {
  const { theme, toggle } = useTheme()
  const { data } = useSession()
  const active = data?.workspaces.find((w) => w.id === data.active_workspace_id) ?? data?.workspaces[0]
  // Notificações em tempo real (RF17) — escopadas no workspace ativo.
  useNotificationsChannel(active?.id)

  return (
    <div className="min-h-screen bg-background text-foreground md:grid md:grid-cols-[256px_1fr]">
      <Sidebar workspaceName={active?.name} userEmail={data?.user.email} />

      <div className="flex flex-col min-w-0 min-h-screen">
        <TopBar theme={theme} onToggleTheme={toggle} />
        <main className="flex-1 overflow-y-auto px-4 md:px-8 py-6 pb-20 md:pb-6">
          <Outlet />
        </main>
      </div>

      <BottomNav />
    </div>
  )
}

function Sidebar({ workspaceName, userEmail }: { workspaceName?: string; userEmail?: string }) {
  return (
    <aside className="hidden md:flex flex-col bg-muted border-r border-border px-2.5 py-3.5">
      <div className="flex items-center gap-2.5 px-2.5 pt-2 pb-4 font-display text-[15px] font-semibold tracking-tight">
        <WalletLogo size={20} />
        <span>Controle Financeiro</span>
      </div>

      <nav className="flex flex-col gap-0.5">
        {NAV_ITEMS.map((item) => (
          <SidebarItem key={item.id} item={item} />
        ))}
      </nav>

      <div className="mt-auto pt-3 border-t border-border">
        <div className="flex items-center gap-2.5 px-1.5 py-2">
          <div className="h-7 w-7 rounded-full bg-foreground text-background inline-flex items-center justify-center text-[11px] font-semibold shrink-0">
            {workspaceName?.charAt(0).toUpperCase() ?? '?'}
          </div>
          <div className="min-w-0">
            <div className="text-[13px] font-medium truncate">{workspaceName ?? '—'}</div>
            <div className="text-[11px] text-muted-foreground truncate">{userEmail ?? ''}</div>
          </div>
        </div>
      </div>
    </aside>
  )
}

function SidebarItem({ item }: { item: NavItem }) {
  const base =
    'flex items-center gap-2.5 px-2.5 py-2 rounded-md text-[13px] transition-colors'
  if (!item.to) {
    return (
      <span
        className={`${base} text-muted-foreground/60 cursor-not-allowed`}
        title="Em breve"
        data-testid={`nav-${item.id}`}
      >
        <item.Icon size={16} />
        <span>{item.label}</span>
        <span className="ml-auto text-[10px] text-muted-foreground/60">em breve</span>
      </span>
    )
  }
  return (
    <NavLink
      to={item.to}
      end={item.to === '/'}
      data-testid={`nav-${item.id}`}
      className={({ isActive }) =>
        `${base} ${
          isActive
            ? 'bg-background text-foreground font-medium shadow-[0_0_0_1px_var(--border)]'
            : 'text-muted-foreground hover:text-foreground hover:bg-foreground/5'
        }`
      }
    >
      <item.Icon size={16} />
      <span>{item.label}</span>
      {item.id === 'inbox' && <span className="ml-auto"><InboxBadge variant="count" /></span>}
    </NavLink>
  )
}

function TopBar({ theme, onToggleTheme }: { theme: string; onToggleTheme: () => void }) {
  return (
    <header className="flex items-center gap-4 h-14 px-4 md:px-8 border-b border-border bg-background shrink-0">
      <div className="flex items-center gap-2 md:hidden font-display text-sm font-semibold">
        <WalletLogo size={18} />
      </div>
      <div className="flex-1 max-w-xl relative items-center hidden sm:flex">
        <Search size={14} className="absolute left-3 text-muted-foreground pointer-events-none" />
        <input
          placeholder="Buscar gastos, tags, contas…"
          className="h-9 w-full rounded-md border border-input bg-background pl-9 pr-3 text-sm text-foreground placeholder:text-muted-foreground focus:border-ring focus:outline-2 focus:outline-ring/30"
        />
      </div>
      <div className="ml-auto flex items-center gap-3">
        <GlobalSyncIndicator />
        <button
          onClick={onToggleTheme}
          aria-label="Alternar tema"
          data-testid="theme-toggle"
          className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground"
        >
          {theme === 'dark' ? <Sun size={16} /> : <Moon size={16} />}
        </button>
        <NotificationsBell />
      </div>
    </header>
  )
}

function BottomNav() {
  const location = useLocation()
  const navigate = useNavigate()
  return (
    <nav className="md:hidden fixed bottom-0 inset-x-0 h-14 bg-background border-t border-border z-30 flex">
      {NAV_ITEMS.map((item) => {
        const isActive = item.to
          ? item.to === '/'
            ? location.pathname === '/'
            : location.pathname.startsWith(item.to)
          : false
        return (
          <button
            key={item.id}
            disabled={!item.to}
            onClick={() => item.to && navigate(item.to)}
            className={`flex-1 flex flex-col items-center justify-center gap-0.5 text-[10px] ${
              isActive ? 'text-foreground font-medium' : 'text-muted-foreground'
            } disabled:opacity-40`}
          >
            <item.Icon size={20} />
            <span>{item.label}</span>
          </button>
        )
      })}
    </nav>
  )
}
