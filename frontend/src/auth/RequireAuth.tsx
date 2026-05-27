import { Navigate, useLocation } from 'react-router'
import { useSession } from './useSession'
import type { ReactNode } from 'react'

/**
 * Guard de rota. Espera o /sessions/current resolver:
 *   - loading  → tela "carregando" muito sutil (não bloquear visualmente)
 *   - null     → redirect pra /login (preservando location pra retornar depois)
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

  return <>{children}</>
}
