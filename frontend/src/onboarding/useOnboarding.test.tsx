import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useAdvanceOnboarding, useSkipOnboarding } from './useOnboarding'
import { SESSION_KEY, type SessionPayload, type OnboardingStatus } from '../auth/useSession'

function mockFetch(body: unknown) {
  const fn = vi.fn(async () => ({ ok: true, status: 200, json: async () => body }) as Response)
  globalThis.fetch = fn as unknown as typeof fetch
  return fn
}

function setup(sessionStatus: string) {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  // Sessão semeada com onboarding AINDA ativo (o cache velho que o RequireAuth lê).
  qc.setQueryData<SessionPayload>(SESSION_KEY, {
    user: { id: 'u1', email: 'k@x.co', name: 'Kaleb', avatar_url: null },
    workspaces: [{ id: 'w1', name: 'WS' }],
    active_workspace_id: 'w1',
    onboarding: { status: sessionStatus as OnboardingStatus, current_step: 3 },
  })
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
  return { qc, wrapper }
}

const sessionOnboarding = (qc: QueryClient) =>
  qc.getQueryData<SessionPayload>(SESSION_KEY)!.onboarding!

describe('useOnboarding mutations — sincronização com a sessão', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('advance→completed patcha o onboarding da sessão na hora (sem esperar refetch)', async () => {
    // Reproduz o loop do "Concluir": a sessão em cache ainda diz "tagging".
    const { qc, wrapper } = setup('tagging')
    mockFetch({ status: 'completed', current_step: null, started_at: null, completed_at: '2026-07-07T00:00:00Z', analysis_error: null })

    const { result } = renderHook(() => useAdvanceOnboarding(), { wrapper })
    await act(async () => {
      await result.current.mutateAsync()
    })

    // Sem o patch síncrono, o RequireAuth veria "tagging" (ativo) e faria bounce
    // pra /onboarding, mostrando o passo 1.
    expect(sessionOnboarding(qc).status).toBe('completed')
    expect(sessionOnboarding(qc).current_step).toBeNull()
  })

  it('skip patcha a sessão pra "skipped" na hora', async () => {
    const { qc, wrapper } = setup('tagging')
    mockFetch({ status: 'skipped', current_step: null, started_at: null, completed_at: null, analysis_error: null })

    const { result } = renderHook(() => useSkipOnboarding(), { wrapper })
    await act(async () => {
      await result.current.mutateAsync()
    })

    expect(sessionOnboarding(qc).status).toBe('skipped')
  })
})
