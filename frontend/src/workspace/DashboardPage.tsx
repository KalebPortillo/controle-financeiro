import { Link } from 'react-router'
import { useSession, useLogout, useSelectWorkspace } from '../auth/useSession'
import { Button } from '../components/Button'
import { buttonClass } from '../components/buttonClass'
import { Card, CardBody, CardHeader } from '../components/Card'
import { MembersCard } from './MembersCard'
import { ConnectBankButton } from '../bank/ConnectBankButton'

/**
 * "Mais" — landing de configurações/workspace (RF16). Vive dentro do AppLayout
 * (o chrome — sidebar/topbar — é do shell). Mostra o usuário/workspace ativo,
 * troca de workspace, membros, conectar banco e sair.
 */
export function DashboardPage() {
  const { data } = useSession()
  const logout = useLogout()
  const select = useSelectWorkspace()

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

      {active && <MembersCard workspaceId={active.id} />}

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
    </div>
  )
}
