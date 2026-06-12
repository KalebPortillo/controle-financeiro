import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router'
import { QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'sonner'
import * as Sentry from '@sentry/react'
import './index.css'
import App from './App.tsx'
import { initSentry } from './sentry'
import { createQueryClient } from './api/queryClient'
import { registerServiceWorker } from './pwa/registerSW'

initSentry()
registerServiceWorker()

// Feedback uniforme de erro: o QueryClient dispara toast por mutation falha.
const queryClient = createQueryClient()

const SentryErrorBoundary = Sentry.ErrorBoundary

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <SentryErrorBoundary
      fallback={({ error }) => (
        <main className="min-h-screen bg-background text-foreground flex items-center justify-center p-8">
          <div className="max-w-md space-y-2 text-center">
            <p className="text-sm font-semibold text-destructive">Algo deu errado</p>
            <p className="text-xs text-muted-foreground font-mono">
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
        {/* Toasts sóbrios (design system): feedback de erro de qualquer ação. */}
        <Toaster position="bottom-right" theme="system" closeButton richColors={false} />
      </QueryClientProvider>
    </SentryErrorBoundary>
  </StrictMode>,
)
