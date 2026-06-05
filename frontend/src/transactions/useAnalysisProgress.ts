import { useQuery } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

export type AnalysisProgress = {
  total: number
  analyzed: number
  done: boolean
}

export type AnalysisProgressView = AnalysisProgress & {
  /** Fração 0..1 analisada (1 quando não há nada pendente). */
  pct: number
}

const empty: AnalysisProgress = { total: 0, analyzed: 0, done: true }

/**
 * Progresso REAL da análise IA (P4/P5). Faz polling enquanto `enabled` e a
 * análise não terminou; a barra anda em degraus de batch (cada lote concluído
 * marca mais transações como analisadas). Para de pollar quando `done`.
 */
export function useAnalysisProgress(enabled: boolean, intervalMs = 1500): AnalysisProgressView {
  const { data } = useQuery({
    queryKey: ['transactions', 'analysis_progress'],
    enabled,
    queryFn: () => apiFetch<AnalysisProgress>('/api/v1/transactions/analysis_progress'),
    // Continua o polling só enquanto há trabalho; para quando done.
    refetchInterval: (query) =>
      enabled && query.state.data && !query.state.data.done ? intervalMs : false,
  })

  const progress = data ?? empty
  const pct = progress.total === 0 ? 1 : progress.analyzed / progress.total
  return { ...progress, pct }
}
