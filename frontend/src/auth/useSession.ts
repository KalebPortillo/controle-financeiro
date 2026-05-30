import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiFetch, UnauthorizedError } from '../api/client'

export type SessionUser = {
  id: string
  email: string
  name: string
  avatar_url: string | null
}

export type SessionWorkspace = {
  id: string
  name: string
}

export type OnboardingStatus =
  | 'not_started'
  | 'connecting'
  | 'analyzing'
  | 'tagging'
  | 'categorizing'
  | 'completed'
  | 'skipped'

export type OnboardingSummary = {
  status: OnboardingStatus | null
  current_step: number | null
}

export type SessionPayload = {
  user: SessionUser
  workspaces: SessionWorkspace[]
  active_workspace_id: string | null
  onboarding: OnboardingSummary | null
}

export const SESSION_KEY = ['session'] as const

/**
 * Carrega a sessão atual. Quando o usuário não está logado, a query
 * resolve para `null` (em vez de erro) — facilita o consumer (LoginPage /
 * Dashboard) decidir o que renderizar sem try/catch.
 */
export function useSession() {
  return useQuery<SessionPayload | null>({
    queryKey: SESSION_KEY,
    queryFn: async ({ signal }) => {
      try {
        return await apiFetch<SessionPayload>('/api/v1/sessions/current', { signal })
      } catch (err) {
        if (err instanceof UnauthorizedError) return null
        throw err
      }
    },
    retry: false,
    staleTime: 30_000,
  })
}

export function useLogout() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => apiFetch<void>('/api/v1/sessions/current', { method: 'DELETE' }),
    onSuccess: () => {
      qc.setQueryData(SESSION_KEY, null)
    },
  })
}

export function useSelectWorkspace() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (workspaceId: string) =>
      apiFetch<{ active_workspace_id: string }>(
        '/api/v1/sessions/current/select_workspace',
        { method: 'POST', body: { workspace_id: workspaceId } }
      ),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: SESSION_KEY })
    },
  })
}
