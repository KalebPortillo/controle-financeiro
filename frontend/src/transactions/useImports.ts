import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

// RF20 — registro de uma importação de arquivo (CSV/OFX).
export type Import = {
  id: string
  filename: string
  format: 'csv' | 'ofx'
  status: 'pending' | 'processing' | 'completed' | 'failed'
  created_count: number
  duplicate_count: number
  error_count: number
  error_log: Array<{ row: number | null; message: string }>
  created_at: string
  completed_at: string | null
}

export const importsKey = ['imports'] as const

export function useImports() {
  return useQuery({
    queryKey: importsKey,
    queryFn: () => apiFetch<{ imports: Import[] }>('/api/v1/imports').then((r) => r.imports),
  })
}

// Status de um import específico, com polling enquanto ainda processa.
export function useImport(id: string | null) {
  return useQuery({
    queryKey: ['imports', id],
    enabled: id !== null,
    queryFn: () => apiFetch<{ import: Import }>(`/api/v1/imports/${id}`).then((r) => r.import),
    refetchInterval: (query) => {
      const s = query.state.data?.status
      return s === 'pending' || s === 'processing' ? 1500 : false
    },
  })
}

// Sobe o arquivo (multipart). format fixo em csv no MVP; account_id opcional.
export function useCreateImport() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: { file: File; format?: 'csv'; accountId?: string }) => {
      const form = new FormData()
      form.append('file', input.file)
      form.append('format', input.format ?? 'csv')
      if (input.accountId) form.append('account_id', input.accountId)
      return apiFetch<{ import: Import }>('/api/v1/imports', { method: 'POST', body: form }).then(
        (r) => r.import,
      )
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: importsKey })
      // O processamento joga itens na inbox — recarrega quando terminar (poll).
      qc.invalidateQueries({ queryKey: ['transactions'] })
    },
  })
}
