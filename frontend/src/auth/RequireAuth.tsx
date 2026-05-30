import { Navigate, useLocation } from 'react-router'
import { useSession, type OnboardingStatus } from './useSession'
import type { ReactNode } from 'react'

// Estados em que o usuário precisa ir pro fluxo de onboarding (RF22).
// Terminais (completed, skipped) liberam o app normal.
const ONBOARDING_ACTIVE_STATUSES: ReadonlySet<OnboardingStatus> = new Set([
  'not_started',
  'connecting',
  'analyzing',
  'tagging',
  'categorizing',
])

/**
 * Guard de rota. Espera o /sessions/current resolver:
 *   - loading  → tela "carregando" muito sutil (não bloquear visualmente)
 *   - null     → redirect pra /login (preservando location pra retornar depois)
 *   - sessão + onboarding ativo → redirect pra /onboarding
 *   - sessão   → renderiza children
 */
export function RequireAuth({ children }: { children: ReactNode }) {
  const { data, isLoading, isError } = useSession()
  const location = useLocation()

  if (isLoading) {
    return (
      <div
        role="status"
        aria-live="polite"
        className="min-h-screen flex items-center justify-center text-xs text-muted-foreground"
      >
        Carregando…
      </div>
    )
  }

  if (isError) {
    // Falha de rede ou 5xx — não temos mais como decidir, mostra fallback.
    return (
      <main className="min-h-screen flex items-center justify-center px-4">
        <div className="text-center space-y-2">
          <p className="text-sm font-medium text-foreground">Não foi possível carregar a sessão</p>
          <p className="text-xs text-muted-foreground">Verifique sua conexão e recarregue a página.</p>
        </div>
      </main>
    )
  }

  if (!data) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />
  }

  // Onboarding ativo (RF22) — redireciona para o fluxo, mas só se o user
  // não está já dentro do /onboarding (evita loop).
  const status = data.onboarding?.status
  const inOnboardingFlow = location.pathname.startsWith('/onboarding')
  if (status && ONBOARDING_ACTIVE_STATUSES.has(status) && !inOnboardingFlow) {
    return <Navigate to="/onboarding" replace />
  }

  return <>{children}</>
}
