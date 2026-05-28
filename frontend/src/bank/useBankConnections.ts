import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

export type ConnectedAccount = {
  id: string
  name: string
  kind: 'checking' | 'credit_card'
  institution: string
  institution_label: string
  currency: string
}

export type BankConnection = {
  id: string
  provider: string
  status: string
  sync_history_since: string
  last_sync_at: string | null
  accounts: ConnectedAccount[]
}

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

// Default sugerido pro histórico inicial (RF1.7): 1º de janeiro do ano corrente.
export function defaultHistorySince(): string {
  const year = new Date().getFullYear()
  return `${year}-01-01`
}
