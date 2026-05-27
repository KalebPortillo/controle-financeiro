import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import * as Sentry from '@sentry/react'
import './index.css'
import App from './App.tsx'
import { initSentry } from './sentry'

initSentry()

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Sem usuários reais ainda — retry agressivo causaria ruído em dev.
      retry: 1,
      staleTime: 30_000,
    },
  },
})

const SentryErrorBoundary = Sentry.ErrorBoundary

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <SentryErrorBoundary
      fallback={({ error }) => (
        <main className="min-h-screen flex items-center justify-center p-8">
          <div className="max-w-md space-y-2 text-center">
            <p className="text-sm font-semibold text-red-600">Algo deu errado</p>
            <p className="text-xs text-neutral-500 font-mono">
              {error instanceof Error ? error.message : String(error)}
            </p>
          </div>
        </main>
      )}
    >
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <App />
        </BrowserRouter>
      </QueryClientProvider>
    </SentryErrorBoundary>
  </StrictMode>,
)
