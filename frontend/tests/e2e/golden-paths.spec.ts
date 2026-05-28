import { test, expect } from '@playwright/test'
import { signIn, goto } from './helpers'

/**
 * Golden paths do RF16 (auth + workspace). Cobre o que o usuário
 * realmente faz: chegar, logar, ver dashboard, sair. Sem edge cases
 * (esses ficam em testes específicos quando entrarem em conflito).
 *
 * Cada teste cria seu próprio usuário (email único via Date.now())
 * pra não interferir com outros. Em CI a base é dropada/recriada
 * entre runs, mas dentro de um run os testes rodam serializados.
 */

const uniqueEmail = (label: string) => `${label}-${Date.now()}@example.com`

test('visitor anônimo é redirecionado pra /login', async ({ page }) => {
  await goto(page, '/')
  await expect(page).toHaveURL(/\/login$/)
  await expect(page.getByRole('heading', { name: /controle financeiro/i })).toBeVisible()
  await expect(page.getByTestId('google-login')).toBeVisible()
})

test('user logado vê o dashboard com nome + workspace', async ({ page, context }) => {
  const email = uniqueEmail('kaleb')
  await signIn(context, { email, name: 'Kaleb Portilho' })

  await goto(page, '/')
  await expect(page).toHaveURL('/')
  await expect(page.getByRole('heading', { name: /olá, kaleb/i })).toBeVisible()
  // Workspace + email vivem no rodapé da sidebar do app shell (o "id-card" oficial).
  // O nome do workspace também aparece no corpo, então escopamos na sidebar.
  await expect(page.locator('aside').getByText("Kaleb Portilho's workspace")).toBeVisible()
  await expect(page.locator('aside').getByText(email)).toBeVisible()
})

test('logout volta pra tela de login', async ({ page, context }) => {
  await signIn(context, { email: uniqueEmail('logout'), name: 'Logout User' })
  await goto(page, '/')

  await page.getByTestId('logout-button').click()
  await expect(page).toHaveURL(/\/login$/)

  // Visitar / direto volta a redirecionar (cookie limpo).
  await goto(page, '/')
  await expect(page).toHaveURL(/\/login$/)
})

test('sessão persiste após reload', async ({ page, context }) => {
  const email = uniqueEmail('persist')
  await signIn(context, { email, name: 'Persistent User' })
  await goto(page, '/')
  await expect(page.getByRole('heading', { name: /olá, persistent/i })).toBeVisible()

  await page.reload({ waitUntil: 'networkidle' })
  await expect(page).toHaveURL('/')
  await expect(page.getByRole('heading', { name: /olá, persistent/i })).toBeVisible()
})

test('convite por email já cadastrado adiciona o membro', async ({ page, context }) => {
  // Cria o convidado primeiro (precisa existir no DB pelo email).
  const inviteeEmail = uniqueEmail('wife')
  await signIn(context, { email: inviteeEmail, name: 'Wife' })

  // Limpa sessão e loga como o "dono" do workspace.
  await context.clearCookies()
  const ownerEmail = uniqueEmail('owner')
  await signIn(context, { email: ownerEmail, name: 'Owner' })

  await goto(page, '/')
  await page.getByTestId('invite-email').fill(inviteeEmail)
  await page.getByTestId('invite-submit').click()

  await expect(page.getByTestId('invite-feedback')).toHaveText(/convite adicionado/i)
  // O nome do convidado aparece na lista de membros após o reload da query.
  await expect(page.getByTestId('members-list')).toContainText('Wife')
})

test('convite por email não cadastrado mostra erro amigável', async ({ page, context }) => {
  await signIn(context, { email: uniqueEmail('lonely'), name: 'Lonely' })
  await goto(page, '/')

  await page.getByTestId('invite-email').fill('nobody-here@example.com')
  await page.getByTestId('invite-submit').click()

  await expect(page.getByTestId('invite-feedback')).toHaveText(/ainda não tem conta/i)
})
