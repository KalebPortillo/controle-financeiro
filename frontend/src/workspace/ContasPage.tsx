import { SyncStatusPanel } from '../bank/SyncStatusPanel'
import { ConnectBankButton } from '../bank/ConnectBankButton'
import { useBankConnectionsChannel } from '../bank/useBankConnectionsChannel'
import { useSession } from '../auth/useSession'
import { Card, CardBody, CardHeader } from '../components/Card'

/**
 * Tela de contas e sincronização (RF21.1). Vive dentro do AppLayout. Lista as
 * conexões com status em tempo real e expõe as ações de sync.
 */
export function ContasPage() {
  const { data } = useSession()
  // Espelha o current_workspace do backend: ativo da sessão ou o primeiro.
  const activeWorkspaceId =
    data?.workspaces.find((w) => w.id === data.active_workspace_id)?.id ??
    data?.workspaces[0]?.id
  useBankConnectionsChannel(activeWorkspaceId)

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <section className="space-y-1">
        <h1 className="font-sans text-2xl font-semibold tracking-tight">
          Contas e sincronização
        </h1>
        <p className="text-sm text-muted-foreground">
          Acompanhe o status das conexões e force uma atualização quando precisar.
        </p>
      </section>

      <Card>
        <CardHeader>
          <h2 className="font-sans text-sm font-medium">Conectar banco</h2>
          <p className="text-xs text-muted-foreground">
            Conecte uma conta via Pluggy. As transações caem na inbox pra você revisar.
          </p>
        </CardHeader>
        <CardBody className="pt-0">
          <ConnectBankButton />
        </CardBody>
      </Card>

      <SyncStatusPanel />
    </div>
  )
}
