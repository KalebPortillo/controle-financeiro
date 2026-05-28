import { useState } from 'react'
import { Card, CardBody, CardHeader } from '../components/Card'
import { Button } from '../components/Button'
import {
  useBankConnectionsList,
  useSyncConnection,
  useSyncAll,
  useSyncHistory,
  type BankConnection,
  type ConnectionStatus,
  type SyncRun,
} from './useBankConnections'

const STATUS_LABEL: Record<ConnectionStatus, string> = {
  connected: 'Conectado',
  syncing: 'Sincronizando',
  expired: 'Expirado',
  error: 'Erro',
  disconnected: 'Desconectado',
}

const STATUS_CLASS: Record<ConnectionStatus, string> = {
  connected: 'text-success',
  syncing: 'text-primary',
  expired: 'text-destructive',
  error: 'text-destructive',
  disconnected: 'text-muted-foreground',
}

function relativeTime(iso: string | null): string {
  if (!iso) return 'Nunca sincronizado'
  const min = Math.round((Date.now() - new Date(iso).getTime()) / 60000)
  if (min < 1) return 'agora mesmo'
  if (min < 60) return `há ${min} min`
  const h = Math.round(min / 60)
  if (h < 24) return `há ${h} h`
  return `há ${Math.round(h / 24)} d`
}

/**
 * Painel de status de sincronização (RF21). Lista as conexões do workspace
 * ativo com status, última sync e erro; permite disparar sync individual
 * (RF21.3) e de todas (RF21.4). O avanço de status chega em tempo real via
 * Action Cable (ver useBankConnectionsChannel).
 */
export function SyncStatusPanel() {
  const { data, isLoading } = useBankConnectionsList()
  const syncAll = useSyncAll()
  const hasConnections = (data?.connections.length ?? 0) > 0

  return (
    <Card>
      <CardHeader className="flex items-start justify-between gap-2">
        <div>
          <h2 className="font-sans text-sm font-medium">Sincronização</h2>
          <p className="text-xs text-muted-foreground">
            Status das conexões bancárias do workspace.
          </p>
        </div>
        {hasConnections && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => syncAll.mutate()}
            disabled={syncAll.isPending}
            data-testid="sync-all"
          >
            {syncAll.isPending ? 'Enviando…' : 'Sincronizar todas'}
          </Button>
        )}
      </CardHeader>

      <CardBody className="pt-0 space-y-3">
        {isLoading && <p className="text-xs text-muted-foreground">Carregando…</p>}
        {!isLoading && !hasConnections && (
          <p className="text-xs text-muted-foreground" data-testid="sync-empty">
            Nenhuma conexão ainda. Conecte um banco para começar.
          </p>
        )}
        {data?.connections.map((c) => (
          <ConnectionRow key={c.id} connection={c} />
        ))}
      </CardBody>
    </Card>
  )
}

function ConnectionRow({ connection: c }: { connection: BankConnection }) {
  const sync = useSyncConnection()
  const [showHistory, setShowHistory] = useState(false)
  const institution = c.accounts[0]?.institution_label ?? 'Conexão'
  const accountNames = c.accounts.map((a) => a.name).join(' · ')

  return (
    <div
      className="rounded-md border border-border p-3 space-y-2"
      data-testid={`connection-${c.id}`}
    >
      <div className="flex items-center justify-between gap-2">
        <div className="min-w-0">
          <div className="text-sm font-medium text-foreground truncate">{institution}</div>
          <div className="text-[11px] text-muted-foreground truncate">
            {accountNames || '—'}
          </div>
        </div>
        <span className={`text-xs font-medium shrink-0 ${STATUS_CLASS[c.status]}`}>
          {STATUS_LABEL[c.status]}
        </span>
      </div>

      {c.error_message && (
        <p className="text-xs text-destructive" role="alert">
          {c.error_message}
        </p>
      )}

      <div className="flex items-center justify-between gap-2">
        <div
          className="text-[11px] text-muted-foreground"
          title={c.last_sync_at ?? undefined}
        >
          {relativeTime(c.last_sync_at)}
          {c.last_sync_at && (
            <>
              {' · '}
              {c.last_sync_created_count} novas, {c.last_sync_duplicate_count} dup
            </>
          )}
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => sync.mutate(c.id)}
          disabled={sync.isPending || c.status === 'syncing'}
          data-testid={`sync-now-${c.id}`}
        >
          {c.status === 'syncing' ? 'Sincronizando…' : 'Sincronizar agora'}
        </Button>
      </div>

      <button
        type="button"
        className="text-[11px] text-muted-foreground hover:text-foreground"
        onClick={() => setShowHistory((v) => !v)}
        data-testid={`history-toggle-${c.id}`}
      >
        {showHistory ? 'Ocultar histórico' : 'Histórico'}
      </button>

      {showHistory && <SyncHistory connectionId={c.id} />}
    </div>
  )
}

function SyncHistory({ connectionId }: { connectionId: string }) {
  const { data: runs, isLoading } = useSyncHistory(connectionId, true)

  if (isLoading) return <p className="text-[11px] text-muted-foreground">Carregando histórico…</p>
  if (!runs || runs.length === 0) {
    return (
      <p className="text-[11px] text-muted-foreground" data-testid={`history-empty-${connectionId}`}>
        Nenhuma sincronização ainda.
      </p>
    )
  }

  return (
    <ul className="space-y-1 border-t border-border pt-2" data-testid={`history-${connectionId}`}>
      {runs.map((run) => (
        <HistoryRow key={run.id} run={run} />
      ))}
    </ul>
  )
}

function HistoryRow({ run }: { run: SyncRun }) {
  const ok = run.status === 'success'
  return (
    <li className="flex items-center justify-between gap-2 text-[11px]">
      <span className="text-muted-foreground" title={run.started_at}>
        {relativeTime(run.started_at)}
        {run.duration_seconds != null && ` · ${run.duration_seconds}s`}
      </span>
      <span className={ok ? 'text-muted-foreground' : 'text-destructive'}>
        {ok
          ? `${run.created_count} novas, ${run.duplicate_count} dup`
          : (run.error_message ?? 'erro')}
      </span>
    </li>
  )
}
