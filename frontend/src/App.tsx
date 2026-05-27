import { Routes, Route, useSearchParams, Navigate } from 'react-router'
import { LoginPage } from './auth/LoginPage'
import { RequireAuth } from './auth/RequireAuth'
import { DashboardPage } from './workspace/DashboardPage'
import { useSession } from './auth/useSession'

/**
 * Roteamento:
 *   /login — pública. Mostra a tela de login (sempre, mesmo já logado:
 *            o user pode estar testando "como é entrar").
 *   /      — protegida. RequireAuth manda pra /login se não tem sessão.
 *
 * O callback OAuth (/api/v1/auth/google_oauth2/callback) é tratado pelo
 * Rails; ele finaliza redirecionando pra '/'. Quando chegamos em '/' com
 * uma sessão ativa, RequireAuth deixa passar.
 */
export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginRoute />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <DashboardPage />
          </RequireAuth>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

/**
 * Se o user já tem sessão (ex.: navegou pra /login depois de logado),
 * manda pra dashboard. Se veio com ?auth_error=... do callback, repassa
 * pro LoginPage como aviso.
 */
function LoginRoute() {
  const [params] = useSearchParams()
  const { data, isLoading } = useSession()
  if (isLoading) return null
  if (data) return <Navigate to="/" replace />
  return <LoginPage error={params.get('auth_error')} />
}
