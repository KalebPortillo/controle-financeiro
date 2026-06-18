import { Link } from 'react-router'
import { CreditCard, Tag as TagIcon, Folder, Upload, Repeat2, ChevronRight, Sun, Moon } from 'lucide-react'
import { useSession, useLogout, useSelectWorkspace } from '../auth/useSession'
import { useTheme } from '../components/useTheme'
import { Button } from '../components/Button'
import { Card, CardBody, CardHeader } from '../components/Card'
import { MembersCard } from './MembersCard'
import { TelegramCard } from '../notifications/TelegramCard'
import { InstallAppCard } from '../pwa/InstallAppCard'

/**
 * "Mais" — landing de configurações/workspace (RF16). Vive dentro do AppLayout
 * (o chrome — sidebar/topbar — é do shell). Mostra o usuário/workspace ativo,
 * troca de workspace, membros e sair.
 */
export function DashboardPage() {
  const { data } = useSession()
  const logout = useLogout()
  const select = useSelectWorkspace()
  const { theme, toggle } = useTheme()

  if (!data) return null // RequireAuth garante que não chegamos aqui logged out.

  const active = data.workspaces.find((w) => w.id === data.active_workspace_id) ?? data.workspaces[0]

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <section className="flex items-start justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-sans text-2xl font-semibold tracking-tight">
            Olá, {data.user.name.split(' ')[0]}
          </h1>
          <p className="text-sm text-muted-foreground">
            Workspace ativo: <span className="text-foreground">{active?.name ?? '—'}</span>
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => logout.mutate()}
          disabled={logout.isPending}
          data-testid="logout-button"
        >
          {logout.isPending ? 'Saindo…' : 'Sair'}
        </Button>
      </section>

      {data.workspaces.length > 1 && (
        <Card>
          <CardHeader>
            <h2 className="font-sans text-sm font-medium">Trocar de workspace</h2>
          </CardHeader>
          <CardBody className="flex flex-wrap gap-2 pt-0">
            {data.workspaces.map((w) => (
              <Button
                key={w.id}
                variant={w.id === active?.id ? 'primary' : 'outline'}
                size="sm"
                onClick={() => select.mutate(w.id)}
                disabled={select.isPending}
                data-testid={`workspace-pick-${w.id}`}
              >
                {w.name}
              </Button>
            ))}
          </CardBody>
        </Card>
      )}

      <InstallAppCard />

      {active && <MembersCard workspaceId={active.id} />}

      <TelegramCard />

      <Card className="overflow-hidden">
        <button
          onClick={toggle}
          data-testid="theme-toggle"
          className="flex w-full items-center gap-3 px-4 py-3 border-b border-border text-left hover:bg-muted transition-colors"
        >
          <span className="text-muted-foreground">{theme === 'dark' ? <Moon size={16} /> : <Sun size={16} />}</span>
          <span className="flex-1 min-w-0">
            <span className="block text-sm font-medium">Tema</span>
            <span className="block text-xs text-muted-foreground">{theme === 'dark' ? 'escuro' : 'claro'}</span>
          </span>
        </button>
        <SectionRow to="/contas" icon={<CreditCard size={16} />} title="Contas e sincronização" sub="Pluggy + status de sync" testid="go-contas" />
        <SectionRow to="/tags" icon={<TagIcon size={16} />} title="Tags" sub="planas, múltiplas por gasto" testid="go-tags" />
        <SectionRow to="/categorias" icon={<Folder size={16} />} title="Categorias" sub="agrega tags" testid="go-categorias" />
        <SectionRow to="/transferencias" icon={<Repeat2 size={16} />} title="Movimentações internas" sub="transferências entre suas contas" testid="go-transferencias" />
        <SectionRow to="/importar" icon={<Upload size={16} />} title="Importar arquivo" sub="extratos CSV pra inbox" testid="go-importar" />
      </Card>
    </div>
  )
}

function SectionRow({
  to, icon, title, sub, testid,
}: {
  to?: string
  icon: React.ReactNode
  title: string
  sub: string
  testid?: string
}) {
  const inner = (
    <>
      <span className="text-muted-foreground">{icon}</span>
      <span className="flex-1 min-w-0">
        <span className="block text-sm font-medium">{title}</span>
        <span className="block text-xs text-muted-foreground">{sub}</span>
      </span>
      {to && <ChevronRight size={14} className="text-muted-foreground" />}
    </>
  )
  const cls =
    'flex items-center gap-3 px-4 py-3 border-b border-border last:border-b-0'
  if (!to) {
    return <div className={`${cls} opacity-50`}>{inner}</div>
  }
  return (
    <Link to={to} className={`${cls} hover:bg-muted transition-colors`} data-testid={testid}>
      {inner}
    </Link>
  )
}
