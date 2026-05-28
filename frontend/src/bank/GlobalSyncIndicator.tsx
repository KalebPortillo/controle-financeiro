import { Link } from 'react-router'
import { useBankConnectionsList } from './useBankConnections'

/**
 * Indicador global discreto de sync (RF21.5). Sumariza as conexões do workspace
 * (erro > sincronizando > conectadas, nessa prioridade de sinal) e leva ao
 * painel `/contas`. Some quando não há conexões.
 */
export function GlobalSyncIndicator() {
  const { data } = useBankConnectionsList()
  const s = data?.summary
  if (!s || s.total === 0) return null

  const { label, tone } =
    s.error > 0
      ? { label: `${s.error} com erro`, tone: 'text-destructive' }
      : s.syncing > 0
        ? { label: `${s.syncing} sincronizando`, tone: 'text-primary' }
        : { label: `${s.connected} conectada${s.connected === 1 ? '' : 's'}`, tone: 'text-muted-foreground' }

  return (
    <Link
      to="/contas"
      className={`flex items-center gap-1.5 text-xs ${tone} hover:opacity-80`}
      title="Status de sincronização"
      data-testid="global-sync-indicator"
    >
      <span className="h-1.5 w-1.5 rounded-full bg-current" />
      {label}
    </Link>
  )
}
