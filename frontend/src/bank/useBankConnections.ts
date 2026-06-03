import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

export type ConnectedAccount = {
  id: string
  name: string
  kind: 'checking' | 'credit_card'
  institution: string
  institution_label: string
  currency: string
}

export type ConnectionStatus =
  | 'connected'
  | 'syncing'
  | 'expired'
  | 'error'
  | 'disconnected'

export type BankConnection = {
  id: string
  provider: string
  status: ConnectionStatus
  error_message: string | null
  sync_history_since: string
  last_sync_at: string | null
  next_sync_at: string | null
  last_sync_created_count: number
  last_sync_duplicate_count: number
  last_sync_error_count: number
  last_sync_duration_seconds: number | null
  accounts: ConnectedAccount[]
}

export type ConnectionsSummary = {
  total: number
  connected: number
  syncing: number
  error: number
}

export type BankConnectionsList = {
  connections: BankConnection[]
  summary: ConnectionsSummary
}

export type SyncRun = {
  id: string
  started_at: string
  finished_at: string | null
  duration_seconds: number | null
  status: 'success' | 'error'
  created_count: number
  duplicate_count: number
  error_count: number
  error_message: string | null
}

export const bankConnectionsKey = ['bank_connections'] as const

// Busca o token curto-prazo que o widget Pluggy Connect precisa.
export function useConnectToken() {
  return useMutation({
    mutationFn: () =>
      apiFetch<{ connect_token: string }>('/api/v1/bank_connections/connect_token', {
        method: 'POST',
      }).then((r) => r.connect_token),
  })
}

// Persiste a conexão após o widget retornar o item.
export function useCreateBankConnection() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: { itemId: string; historySince: string }) =>
      apiFetch<{ bank_connection: BankConnection }>('/api/v1/bank_connections', {
        method: 'POST',
        body: { item_id: input.itemId, history_since: input.historySince },
      }).then((r) => r.bank_connection),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank_connections'] })
    },
  })
}

// Lista as conexões do workspace ativo + summary agregado (RF21.1/21.2).
export function useBankConnectionsList() {
  return useQuery({
    queryKey: bankConnectionsKey,
    queryFn: () => apiFetch<BankConnectionsList>('/api/v1/bank_connections'),
  })
}

// "Sincronizar agora" por conexão (RF21.3). O status já volta como `syncing`;
// o avanço seguinte chega via Action Cable.
export function useSyncConnection() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) =>
      apiFetch<{ bank_connection: BankConnection }>(
        `/api/v1/bank_connections/${id}/sync`,
        { method: 'POST' }
      ).then((r) => r.bank_connection),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: bankConnectionsKey })
    },
  })
}

// "Sincronizar todas" (RF21.4).
export function useSyncAll() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () =>
      apiFetch<{ enqueued: number }>('/api/v1/bank_connections/sync_all', {
        method: 'POST',
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: bankConnectionsKey })
    },
  })
}

// Histórico das últimas N syncs de uma conexão (RF21.7). `enabled` só dispara
// o fetch quando o usuário expande o histórico no painel.
export function useSyncHistory(connectionId: string, enabled: boolean) {
  return useQuery({
    queryKey: ['sync_history', connectionId],
    enabled,
    queryFn: () =>
      apiFetch<{ syncs: SyncRun[] }>(
        `/api/v1/bank_connections/${connectionId}/sync_history?limit=10`
      ).then((r) => r.syncs),
  })
}

// Default sugerido pro histórico inicial (RF1.7): 1º de janeiro do ano corrente.
export function defaultHistorySince(): string {
  const year = new Date().getFullYear()
  return `${year}-01-01`
}

// Período de importação do histórico inicial (RF1.7). O usuário escolhe de
// quando começar a puxar transações ao conectar a conta.
export type HistoryPeriod = '1m' | '2m' | '3m' | '6m' | 'custom'

export const HISTORY_PERIOD_OPTIONS: ReadonlyArray<{ value: HistoryPeriod; label: string }> = [
  { value: '1m',     label: 'Último mês' },
  { value: '2m',     label: 'Últimos 2 meses' },
  { value: '3m',     label: 'Últimos 3 meses' },
  { value: '6m',     label: 'Últimos 6 meses' },
  { value: 'custom', label: 'Personalizado' },
]

// Data ISO (YYYY-MM-DD) de N meses atrás, em horário local (sem shift de UTC).
export function monthsAgoISO(n: number, today = new Date()): string {
  const d = new Date(today.getFullYear(), today.getMonth() - n, today.getDate())
  const yyyy = d.getFullYear()
  const mm = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

// Resolve a opção de período (+ data custom opcional) numa data ISO de início.
// Para 'custom' sem data informada, cai no default (1º de janeiro do ano).
export function resolveHistorySince(period: HistoryPeriod, customDate?: string): string {
  switch (period) {
    case '1m': return monthsAgoISO(1)
    case '2m': return monthsAgoISO(2)
    case '3m': return monthsAgoISO(3)
    case '6m': return monthsAgoISO(6)
    case 'custom': return customDate || defaultHistorySince()
  }
}
