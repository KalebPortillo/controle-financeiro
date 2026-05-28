import { Link } from 'react-router'
import { WalletLogo } from '../components/WalletLogo'
import { SyncStatusPanel } from '../bank/SyncStatusPanel'
import { useBankConnectionsChannel } from '../bank/useBankConnectionsChannel'
import { useSession } from '../auth/useSession'

/**
 * Tela dedicada de contas e sincronização (RF21.1). Lista as conexões
 * bancárias do workspace com status em tempo real e expõe as ações de sync.
 */
export function ContasPage() {
  const { data } = useSession()
  // Espelha o current_workspace do backend: ativo da sessão ou o primeiro.
  const activeWorkspaceId =
    data?.workspaces.find((w) => w.id === data.active_workspace_id)?.id ??
    data?.workspaces[0]?.id
  useBankConnectionsChannel(activeWorkspaceId)

  return (
    <main className="min-h-screen bg-background text-foreground">
      <header className="border-b border-border bg-card">
        <div className="max-w-3xl mx-auto px-4 h-14 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-2 text-foreground">
            <WalletLogo size={20} />
            <span className="font-sans text-sm font-medium">Controle financeiro</span>
          </Link>
          <Link to="/" className="text-xs text-muted-foreground hover:text-foreground">
            ← Voltar
          </Link>
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
        <section className="space-y-1">
          <h1 className="font-sans text-xl font-semibold tracking-tight">
            Contas e sincronização
          </h1>
          <p className="text-sm text-muted-foreground">
            Acompanhe o status das conexões e force uma atualização quando precisar.
          </p>
        </section>

        <SyncStatusPanel />
      </div>
    </main>
  )
}
