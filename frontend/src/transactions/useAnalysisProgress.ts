import { useQuery } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

// Erro de IA exposto pela camada de feedback (mesmo formato do onboarding).
export type AiError = { reason: string; message: string; at: string }

// Progresso por estado explícito (ai_status): awaiting (na fila), analyzed
// (a IA rodou), failed (não conseguiu). `done` = ninguém aguardando — failed
// NÃO trava o progresso.
export type AnalysisProgress = {
  total: number
  analyzed: number
  failed: number
  awaiting: number
  done: boolean
  error: AiError | null
}

export type AnalysisProgressView = AnalysisProgress & {
  /** Fração 0..1 já processada (analyzed+failed)/total; 1 quando nada pendente. */
  pct: number
  /** Há gastos ainda aguardando análise (barra "Analisando…"). */
  analyzing: boolean
}

const empty: AnalysisProgress = { total: 0, analyzed: 0, failed: 0, awaiting: 0, done: true, error: null }

/**
 * Progresso REAL da análise IA. Faz polling enquanto `enabled` e há gastos
 * aguardando; para quando não há mais ninguém aguardando (done) ou quando há
 * erro de serviço (o usuário clica "Tentar de novo").
 */
export function useAnalysisProgress(enabled: boolean, intervalMs = 1500): AnalysisProgressView {
  const { data } = useQuery({
    queryKey: ['transactions', 'analysis_progress'],
    enabled,
    queryFn: () => apiFetch<AnalysisProgress>('/api/v1/transactions/analysis_progress'),
    refetchInterval: (query) => {
      const d = query.state.data
      return enabled && d && !d.done && !d.error ? intervalMs : false
    },
  })

  const progress = data ?? empty
  const processed = progress.analyzed + progress.failed
  const pct = progress.total === 0 ? 1 : processed / progress.total
  return { ...progress, pct, analyzing: progress.awaiting > 0 }
}
