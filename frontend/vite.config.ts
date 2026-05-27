import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
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
  test: {
    environment: 'happy-dom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
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
