import { SyncStatusPanel } from '../bank/SyncStatusPanel'
import { useBankConnectionsChannel } from '../bank/useBankConnectionsChannel'
import { useSession } from '../auth/useSession'

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

      <SyncStatusPanel />
    </div>
  )
}
