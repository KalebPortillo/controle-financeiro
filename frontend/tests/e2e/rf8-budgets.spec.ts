import { test, expect } from '@playwright/test'
import { signIn, goto, seed } from './helpers'

/**
 * RF8 — orçamentos. Cria um orçamento por tag pelo wizard e confere que o
 * progresso reflete o gasto consolidado semeado (R$ 400 de R$ 800 = 50%).
 */

const uniqueEmail = (label: string) => `${label}-${Date.now()}@example.com`

test('cria orçamento por tag e vê o progresso do mês', async ({ page, context }) => {
  await signIn(context, { email: uniqueEmail('rf8'), name: 'RF8' })
  const { tag_id } = await seed(context, 'budget_setup')

  await goto(page, '/orcamentos')
  await expect(page.getByTestId('budgets-empty')).toBeVisible()

  // Wizard: passo 1 (tag é o tipo default) → escolher a tag semeada.
  await page.getByTestId('budget-new').click()
  await page.getByTestId(`budget-tag-list-${tag_id}`).click()
  await page.getByTestId('budget-next').click()

  // Passo 2: nome + teto.
  await page.getByTestId('budget-name').fill('Orçamento Mercado')
  await page.getByTestId('budget-limit').fill('800,00')
  await page.getByTestId('budget-save').click()

  // O card aparece com 50% (R$ 400 de R$ 800).
  const card = page.locator('[data-testid^="budget-card-"]').filter({ hasText: 'Orçamento Mercado' })
  await expect(card).toBeVisible()
  await expect(card).toContainText('50%')

  // Abrir o detalhe: histórico multi-mês + a transação que compõe o gasto.
  await card.click()
  await expect(page.getByTestId('budget-history')).toBeVisible()
  await expect(page.getByTestId('budget-transactions')).toContainText('SUPERMERCADO')
  await expect(page.getByTestId('budget-detail-edit')).toBeVisible()
})
