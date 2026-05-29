import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    rollupOptions: {
      output: {
        // Quebra vendor em chunks isoláveis pra reduzir o JS principal e
        // melhorar cache cross-versões: dependências externas mudam pouco
        // comparado ao código da app.
        manualChunks: {
          'react-vendor':    ['react', 'react-dom', 'react-router'],
          'tanstack':        ['@tanstack/react-query'],
          'sentry':          ['@sentry/react'],
          'pluggy':          ['react-pluggy-connect', 'pluggy-connect-sdk'],
          'icons':           ['lucide-react'],
          'cable':           ['@rails/actioncable'],
        },
      },
    },
    chunkSizeWarningLimit: 600,
  },
  server: {
    // Em dev, Vite (porta 5173) faz proxy de /api/v1, /up e /cable pra
    // Rails (porta 3000). Cookies de sessão chegam mesma-origem, sem CORS.
    // Em prod, frontend e backend são servidos pelo mesmo host (Thruster
    // serve o SPA buildado), então o proxy é só artifício de dev.
    proxy: {
      '/api/v1': 'http://localhost:3000',
      '/up':     'http://localhost:3000',
      '/cable':  { target: 'ws://localhost:3000', ws: true },
    },
  },
  preview: {
    // Mesmo proxy do dev — usado pelos E2E (Playwright bate em vite preview).
    proxy: {
      '/api/v1': 'http://localhost:3000',
      '/up':     'http://localhost:3000',
      '/cable':  { target: 'ws://localhost:3000', ws: true },
    },
  },
  test: {
    environment: 'happy-dom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    // Vitest cobre unit/component tests em src/. Playwright (E2E) vive em
    // tests/e2e/ e roda via `npm run test:e2e`.
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      thresholds: {
        lines: 70,
        functions: 70,
        branches: 70,
        statements: 70,
      },
    },
  },
})
