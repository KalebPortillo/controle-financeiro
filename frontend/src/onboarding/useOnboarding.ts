import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'
import { SESSION_KEY, type OnboardingStatus } from '../auth/useSession'

export type SuggestedTag = {
  name: string
  rationale?: string
  coverage?: number
}

export type SuggestedCategory = {
  name: string
  tag_names: string[]
}

export type OnboardingState = {
  status: OnboardingStatus | null
  current_step: number | null
  started_at: string | null
  completed_at: string | null
  suggested_tags: SuggestedTag[]
  suggested_categories: SuggestedCategory[]
  accepted_tag_ids: string[]
  accepted_category_ids: string[]
}

export const ONBOARDING_KEY = ['onboarding'] as const

// Polling em ms só quando o backend muda o status sozinho: "analyzing" (o
// AnalyzeJob termina → vira "tagging"). Em "connecting" o avanço depende do
// clique do usuário (F2), então não há o que esperar via polling.
const POLLING_INTERVAL = 5_000

function shouldPoll(status: OnboardingStatus | null | undefined): number | false {
  if (status === 'analyzing') return POLLING_INTERVAL
  return false
}

export function useOnboarding(enabled = true) {
  return useQuery<OnboardingState>({
    queryKey: ONBOARDING_KEY,
    queryFn: () => apiFetch<OnboardingState>('/api/v1/onboarding'),
    enabled,
    staleTime: 0,
    refetchInterval: (query) => shouldPoll(query.state.data?.status),
  })
}

function makeMutation(path: string, body?: unknown) {
  return () => {
    const qc = useQueryClient()
    return useMutation({
      mutationFn: () => apiFetch<OnboardingState>(path, { method: 'POST', body }),
      onSuccess: (data) => {
        qc.setQueryData(ONBOARDING_KEY, data)
        // Sessão também tem onboarding resumido → invalidar pra próximo redirect
        qc.invalidateQueries({ queryKey: SESSION_KEY })
      },
    })
  }
}

export const useStartOnboarding    = makeMutation('/api/v1/onboarding/start')
export const useSkipOnboarding     = makeMutation('/api/v1/onboarding/skip')
export const useAdvanceOnboarding  = makeMutation('/api/v1/onboarding/advance')
// "Continuar para análise" (F2): avança connecting → analyzing, o que dispara o
// AnalyzeJob no backend. A análise é iniciada pelo usuário, não pelo fim do sync.
export const useStartAnalysis      = makeMutation('/api/v1/onboarding/advance', { to: 'analyzing' })
// Pular a análise da IA: avança analyzing → tagging imediatamente. O AnalyzeJob
// ainda pode estar rodando; se terminar, gravará no catálogo suggested_tags sem
// sobrescrever tags já aceitas (SuggestedTag.record é não-destrutivo).
export const useSkipAnalysis       = makeMutation('/api/v1/onboarding/advance', { to: 'tagging' })

export type AcceptedTag = { name: string }
export type AcceptedCategory = { name: string; tag_ids: string[] }

export function useAcceptOnboardingTags() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: { accepted: AcceptedTag[] }) =>
      apiFetch<OnboardingState>('/api/v1/onboarding/tags', {
        method: 'POST',
        body: input,
      }),
    onSuccess: (data) => {
      qc.setQueryData(ONBOARDING_KEY, data)
      qc.invalidateQueries({ queryKey: SESSION_KEY })
      qc.invalidateQueries({ queryKey: ['tags'] })
    },
  })
}

export function useAcceptOnboardingCategories() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: { accepted: AcceptedCategory[] }) =>
      apiFetch<OnboardingState>('/api/v1/onboarding/categories', {
        method: 'POST',
        body: input,
      }),
    onSuccess: (data) => {
      qc.setQueryData(ONBOARDING_KEY, data)
      qc.invalidateQueries({ queryKey: SESSION_KEY })
      qc.invalidateQueries({ queryKey: ['categories'] })
    },
  })
}
