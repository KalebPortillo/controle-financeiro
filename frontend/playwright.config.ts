import { defineConfig, devices } from '@playwright/test'

/**
 * Playwright config — E2E golden paths.
 *
 * Estratégia:
 *   - Rails roda em :3000 (env=test) com o bypass POST /api/v1/auth/test_sign_in
 *     habilitado.
 *   - Vite preview serve o build de produção em :5173. O Vite proxia /api/v1
 *     pro Rails (mesma config do dev), então testes batem só em :5173.
 *   - Cada teste cria um user único via test_sign_in pra não vazar estado.
 *
 * Os `webServer` abaixo sobem ambos automaticamente — `npm run test:e2e`
 * funciona sem precisar abrir Rails/Vite em outro terminal.
 *
 * Em CI, ambos servidores são iniciados pelo workflow antes (mais previsível
 * de logar quando algo dá errado); definimos os mesmos serviços aqui só pra
 * uso local.
 */
export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: false, // E2E compartilha banco — serializar evita flakiness.
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [ [ 'github' ], [ 'list' ] ] : 'list',

  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],

  // Em CI usaremos `PLAYWRIGHT_REUSE_SERVERS=1` pra pular o webServer
  // (workflow já sobe os processos antes). Local: webServer sobe automático.
  webServer: process.env.PLAYWRIGHT_REUSE_SERVERS ? undefined : [
    {
      command: 'cd ../backend && RAILS_ENV=test bin/rails db:test:prepare && RAILS_ENV=test bin/rails server -p 3000',
      url: 'http://localhost:3000/up',
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
    {
      command: 'npm run build && npm run preview -- --port 5173 --strictPort',
      url: 'http://localhost:5173',
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
  ],
})
