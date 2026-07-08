import type { Page, BrowserContext } from '@playwright/test'

/**
 * Loga um usuário no backend via rota de bypass e devolve os dados básicos.
 * A rota POST /api/v1/auth/test_sign_in só existe em non-production e usa o
 * mesmo `Users::CreateWithPersonalWorkspace` que o callback OAuth real —
 * então o user fica com workspace pessoal e tudo mais.
 *
 * Usa `context.request` (não `page.request`) pra setar o cookie de sessão
 * no contexto inteiro do browser, valendo pras navegações subsequentes.
 */
export async function signIn(
  context: BrowserContext,
  opts: { email: string; name?: string },
) {
  const res = await context.request.post('/api/v1/auth/test_sign_in', {
    data: { email: opts.email, name: opts.name ?? opts.email.split('@')[0] },
  })
  if (!res.ok()) {
    throw new Error(`test_sign_in failed: HTTP ${res.status()} — ${await res.text()}`)
  }
}

/** Garante que `page` recebeu os cookies do contexto antes de navegar. */
export async function goto(page: Page, path: string) {
  await page.goto(path, { waitUntil: 'networkidle' })
}

/**
 * Semeia um cenário de dados no workspace atual (RF23). A rota
 * POST /api/v1/test_support/seed só existe em dev/test (gate Rails.env.local?).
 * Devolve os ids criados pros seletores do teste.
 */
export async function seed(
  context: BrowserContext,
  scenario: 'related_inbox' | 'link_manual',
): Promise<Record<string, string>> {
  const res = await context.request.post('/api/v1/test_support/seed', { data: { scenario } })
  if (!res.ok()) {
    throw new Error(`seed ${scenario} failed: HTTP ${res.status()} — ${await res.text()}`)
  }
  return res.json()
}
