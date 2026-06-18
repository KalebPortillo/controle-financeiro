import { RefreshCw } from 'lucide-react'
import { useBankConnectionsList, useSyncAll } from './useBankConnections'

/**
 * Botão global "sincronizar agora" (RF21.4) no top bar, ao lado do indicador de
 * status. Some quando não há conexões. Enquanto sincroniza — mutação pendente ou
 * alguma conexão em `syncing` — gira o ícone e desabilita (o indicador ao lado
 * passa a mostrar "sincronizando").
 */
export function SyncAllButton() {
  const { data } = useBankConnectionsList()
  const syncAll = useSyncAll()
  if (!data || data.summary.total === 0) return null

  const busy = syncAll.isPending || data.summary.syncing > 0

  return (
    <button
      onClick={() => syncAll.mutate()}
      disabled={busy}
      aria-label="Sincronizar contas agora"
      title="Sincronizar agora"
      data-testid="sync-all-button"
      className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground disabled:opacity-60 disabled:cursor-not-allowed"
    >
      <RefreshCw size={16} className={busy ? 'animate-spin' : ''} />
    </button>
  )
}
