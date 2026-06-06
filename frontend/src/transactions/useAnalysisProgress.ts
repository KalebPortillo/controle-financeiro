import { useQuery } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

// Erro de IA exposto pela camada de feedback (mesmo formato do onboarding).
export type AiError = { reason: string; message: string; at: string }

export type AnalysisProgress = {
  total: number
  analyzed: number
  done: boolean
  error: AiError | null
}

export type AnalysisProgressView = AnalysisProgress & {
  /** Fração 0..1 analisada (1 quando não há nada pendente). */
  pct: number
}

const empty: AnalysisProgress = { total: 0, analyzed: 0, done: true, error: null }

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
    // Continua o polling só enquanto há trabalho; para quando done OU quando há
    // erro (re-tentar sozinho não ajuda — o usuário clica "Tentar de novo").
    refetchInterval: (query) => {
      const d = query.state.data
      return enabled && d && !d.done && !d.error ? intervalMs : false
    },
  })

  const progress = data ?? empty
  const pct = progress.total === 0 ? 1 : progress.analyzed / progress.total
  return { ...progress, pct }
}
