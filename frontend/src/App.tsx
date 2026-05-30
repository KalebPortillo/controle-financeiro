import { lazy, Suspense } from 'react'
import { Routes, Route, useSearchParams, Navigate } from 'react-router'
import { LoginPage } from './auth/LoginPage'
import { RequireAuth } from './auth/RequireAuth'
import { AppLayout } from './app/AppLayout'
import { InboxPage } from './transactions/InboxPage'
import { GastosPage } from './transactions/GastosPage'
import { useSession } from './auth/useSession'

// Lazy: páginas secundárias só carregam quando o usuário navega até elas.
// Reduz o bundle inicial — Inbox e Gastos são a maioria do uso real.
const DashboardPage = lazy(() => import('./workspace/DashboardPage').then(m => ({ default: m.DashboardPage })))
const ContasPage    = lazy(() => import('./workspace/ContasPage').then(m => ({ default: m.ContasPage })))
const TagsPage      = lazy(() => import('./transactions/TagsPage').then(m => ({ default: m.TagsPage })))
const CategoriasPage = lazy(() => import('./transactions/CategoriasPage').then(m => ({ default: m.CategoriasPage })))
const ReportsPage   = lazy(() => import('./transactions/ReportsPage').then(m => ({ default: m.ReportsPage })))
const OnboardingPage = lazy(() => import('./onboarding/OnboardingPage').then(m => ({ default: m.OnboardingPage })))

function LazyPage({ children }: { children: React.ReactNode }) {
  return (
    <Suspense fallback={<p className="text-xs text-muted-foreground p-6">Carregando…</p>}>
      {children}
    </Suspense>
  )
}

/**
 * Roteamento:
 *   /login — pública. Mostra a tela de login (sempre, mesmo já logado).
 *   resto  — protegido, dentro do AppLayout (shell com sidebar/topbar/bottomnav).
 *
 * O callback OAuth (/api/v1/auth/google_oauth2/callback) é tratado pelo
 * Rails; ele finaliza redirecionando pra '/inbox' (landing principal).
 * RequireAuth gateia o shell.
 */
export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginRoute />} />

      {/* Onboarding (RF22) — fullscreen, fora do AppLayout, mas dentro do RequireAuth.
          O próprio RequireAuth redireciona PRA cá quando o status indica fluxo ativo. */}
      <Route
        path="/onboarding"
        element={
          <RequireAuth>
            <LazyPage><OnboardingPage /></LazyPage>
          </RequireAuth>
        }
      />

      <Route
        element={
          <RequireAuth>
            <AppLayout />
          </RequireAuth>
        }
      >
        <Route path="/" element={<Navigate to="/inbox" replace />} />
        <Route path="/inbox" element={<InboxPage />} />
        <Route path="/gastos" element={<GastosPage />} />
        <Route path="/contas" element={<LazyPage><ContasPage /></LazyPage>} />
        <Route path="/tags" element={<LazyPage><TagsPage /></LazyPage>} />
        <Route path="/categorias" element={<LazyPage><CategoriasPage /></LazyPage>} />
        <Route path="/relatorios" element={<LazyPage><ReportsPage /></LazyPage>} />
        <Route path="/mais" element={<LazyPage><DashboardPage /></LazyPage>} />
      </Route>
      <Route path="*" element={<Navigate to="/inbox" replace />} />
    </Routes>
  )
}

/**
 * Se o user já tem sessão (ex.: navegou pra /login depois de logado),
 * manda pra inbox. Se veio com ?auth_error=... do callback, repassa
 * pro LoginPage como aviso.
 */
function LoginRoute() {
  const [params] = useSearchParams()
  const { data, isLoading } = useSession()
  if (isLoading) return null
  if (data) return <Navigate to="/inbox" replace />
  return <LoginPage error={params.get('auth_error')} />
}
