import { Link } from 'react-router'
import { useSession, useLogout, useSelectWorkspace, type SessionPayload } from '../auth/useSession'
import { Button } from '../components/Button'
import { buttonClass } from '../components/buttonClass'
import { Card, CardBody, CardHeader } from '../components/Card'
import { WalletLogo } from '../components/WalletLogo'
import { MembersCard } from './MembersCard'
import { ConnectBankButton } from '../bank/ConnectBankButton'
import { GlobalSyncIndicator } from '../bank/GlobalSyncIndicator'

/**
 * Dashboard mínimo pós-login. RF16 só exige:
 *   - identificar o user logado
 *   - listar workspaces e mostrar qual é o ativo
 *   - permitir trocar de workspace (se >1)
 *   - botão sair
 *
 * Inbox / Gastos / Orçamentos / Relatórios entram em RFs futuros.
 */
export function DashboardPage() {
  const { data } = useSession()
  const logout = useLogout()
  const select = useSelectWorkspace()

  if (!data) return null // RequireAuth garante que não chegamos aqui logged out.

  const active = data.workspaces.find((w) => w.id === data.active_workspace_id) ?? data.workspaces[0]

  return (
    <main className="min-h-screen bg-background text-foreground">
      <Header session={data} onLogout={() => logout.mutate()} logoutPending={logout.isPending} />

      <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
        <section className="space-y-1">
          <h1 className="font-sans text-xl font-semibold tracking-tight">
            Olá, {data.user.name.split(' ')[0]}
          </h1>
          <p className="text-sm text-muted-foreground">
            Workspace ativo: <span className="text-foreground">{active?.name ?? '—'}</span>
          </p>
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

        {active && <MembersCard workspaceId={active.id} />}

        <ConnectBankCard />
      </div>
    </main>
  )
}

function ConnectBankCard() {
  return (
    <Card>
      <CardHeader>
        <h2 className="font-sans text-sm font-medium">Conectar banco</h2>
        <p className="text-xs text-muted-foreground">
          Conecte uma conta via Pluggy. As transações caem na inbox pra você revisar.
        </p>
      </CardHeader>
      <CardBody className="pt-0 flex flex-wrap items-center gap-2">
        <ConnectBankButton />
        <Link
          to="/contas"
          className={buttonClass({ variant: 'outline', size: 'md' })}
          data-testid="go-contas"
        >
          Status de sincronização
        </Link>
      </CardBody>
    </Card>
  )
}

function Header({
  session,
  onLogout,
  logoutPending,
}: {
  session: SessionPayload
  onLogout: () => void
  logoutPending: boolean
}) {
  return (
    <header className="border-b border-border bg-card">
      <div className="max-w-3xl mx-auto px-4 h-14 flex items-center justify-between">
        <div className="flex items-center gap-2 text-foreground">
          <WalletLogo size={20} />
          <span className="font-sans text-sm font-medium">Controle financeiro</span>
        </div>
        <div className="flex items-center gap-3">
          <GlobalSyncIndicator />
          <div className="text-right leading-tight hidden sm:block">
            <div className="text-xs font-medium text-foreground">{session.user.name}</div>
            <div className="text-[11px] text-muted-foreground">{session.user.email}</div>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={onLogout}
            disabled={logoutPending}
            data-testid="logout-button"
          >
            {logoutPending ? 'Saindo…' : 'Sair'}
          </Button>
        </div>
      </div>
    </header>
  )
}

