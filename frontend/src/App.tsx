import { Routes, Route, useSearchParams, Navigate } from 'react-router'
import { LoginPage } from './auth/LoginPage'
import { RequireAuth } from './auth/RequireAuth'
import { AppLayout } from './app/AppLayout'
import { DashboardPage } from './workspace/DashboardPage'
import { ContasPage } from './workspace/ContasPage'
import { InboxPage } from './transactions/InboxPage'
import { GastosPage } from './transactions/GastosPage'
import { TagsPage } from './transactions/TagsPage'
import { useSession } from './auth/useSession'

/**
 * Roteamento:
 *   /login — pública. Mostra a tela de login (sempre, mesmo já logado).
 *   resto  — protegido, dentro do AppLayout (shell com sidebar/topbar/bottomnav).
 *
 * O callback OAuth (/api/v1/auth/google_oauth2/callback) é tratado pelo
 * Rails; ele finaliza redirecionando pra '/'. RequireAuth gateia o shell.
 */
export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginRoute />} />
      <Route
        element={
          <RequireAuth>
            <AppLayout />
          </RequireAuth>
        }
      >
        <Route path="/" element={<DashboardPage />} />
        <Route path="/inbox" element={<InboxPage />} />
        <Route path="/gastos" element={<GastosPage />} />
        <Route path="/contas" element={<ContasPage />} />
        <Route path="/tags" element={<TagsPage />} />
      </Route>
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
