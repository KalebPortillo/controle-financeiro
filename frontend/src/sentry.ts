import * as Sentry from '@sentry/react'

/**
 * Initialize Sentry. Inert quando VITE_SENTRY_DSN ausente (Sentry detecta
 * dsn falsy e não envia eventos, mas não quebra import).
 */
export function initSentry() {
  const dsn = import.meta.env.VITE_SENTRY_DSN
  if (!dsn) return

  Sentry.init({
    dsn,
    environment: import.meta.env.MODE,
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({
        maskAllText: true,
        blockAllMedia: true,
      }),
    ],
    // Desativado pré-MVP — sem usuários reais, traces consomem quota sem valor.
    // Subir para 0.1 quando RF16+ estiver em uso.
    tracesSampleRate: 0.0,
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 1.0,
    sendDefaultPii: false,
  })
}
