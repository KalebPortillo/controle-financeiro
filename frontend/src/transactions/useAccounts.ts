import { useQuery } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

export interface ReportAccount {
  id: string
  name: string
  kind: 'checking' | 'credit_card'
  institution: string
  institution_label: string | null
  last_digits: string | null
  owner_membership_id: string | null
  currency: string
}

// Contas do workspace — alimenta os filtros de relatório (conta/cartão, pessoa).
export function useAccounts() {
  return useQuery<ReportAccount[]>({
    queryKey: ['accounts'],
    queryFn: () => apiFetch<{ accounts: ReportAccount[] }>('/api/v1/accounts').then((r) => r.accounts),
    staleTime: 60_000,
  })
}
