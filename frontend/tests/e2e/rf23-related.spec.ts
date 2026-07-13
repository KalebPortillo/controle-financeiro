import { test, expect } from '@playwright/test'
import { signIn, goto, seed } from './helpers'

/**
 * RF23 — transações relacionadas. Cobre os fluxos que antes eram testados só
 * na mão a cada release:
 *  - Fase 2: agrupamento de compra + IOF no inbox (item único, aceitar o conjunto).
 *  - Fase 3: vínculo manual de um gasto órfão a um gasto de origem.
 *
 * Cada teste cria seu próprio usuário e semeia os dados via /test_support/seed.
 */

const uniqueEmail = (label: string) => `${label}-${Date.now()}@example.com`

test('F2 — compra + IOF agrupados no inbox; aceitar consolida os dois', async ({ page, context }) => {
  await signIn(context, { email: uniqueEmail('rel-f2'), name: 'Rel F2' })
  const { purchase_id, iof_id } = await seed(context, 'related_inbox')

  await goto(page, '/inbox')

  // A compra e o IOF NÃO aparecem como linhas soltas — viram um item de grupo.
  const groupRow = page.getByTestId(`inbox-related-${purchase_id}`)
  await expect(groupRow).toBeVisible()
  await expect(groupRow).toContainText('com IOF')
  await expect(page.getByTestId(`inbox-row-${purchase_id}`)).toHaveCount(0)
  await expect(page.getByTestId(`inbox-row-${iof_id}`)).toHaveCount(0)

  // Abre o sheet do grupo: origem em destaque + a relacionada.
  await groupRow.click()
  await expect(page.getByTestId(`related-sheet-members-${purchase_id}`)).toBeVisible()
  await expect(page.getByTestId(`related-sheet-member-${purchase_id}`)).toContainText('Origem')
  await expect(page.getByTestId(`related-sheet-member-${iof_id}`)).toContainText('IOF')

  // Aceitar todas → o grupo inteiro sai do inbox.
  await page.getByTestId(`related-sheet-accept-${purchase_id}`).click()
  await expect(page.getByTestId(`inbox-related-${purchase_id}`)).toHaveCount(0)
})

test('F3 — vincular manualmente um gasto órfão a um gasto de origem', async ({ page, context }) => {
  await signIn(context, { email: uniqueEmail('rel-f3'), name: 'Rel F3' })
  const { origin_id, orphan_id } = await seed(context, 'link_manual')

  await goto(page, '/gastos')

  // Busca global (ignora o mês) pra achar o órfão consolidado e abrir o detalhe.
  await page.getByTestId('gastos-search').fill('tarifa')
  const orphanRow = page.getByTestId(`gasto-row-${orphan_id}`)
  await expect(orphanRow).toBeVisible()
  await orphanRow.click()

  // Abre o vínculo manual (seção "Vínculos" unificada), escolhe o tipo e busca a origem.
  await page.getByTestId('link-open').click()
  await page.getByTestId('link-type-fee').click()
  await page.getByTestId('link-search').fill('assinatura')
  await page.getByTestId(`link-candidate-${origin_id}`).click()

  // Vinculado: a origem aparece na seção "Vínculos"; o botão de vincular permanece
  // disponível (dá pra acumular mais vínculos).
  await expect(page.getByTestId('links-section')).toBeVisible()
  await expect(page.getByTestId(`link-open-${origin_id}`)).toContainText('Origem')
  await expect(page.getByTestId('link-open')).toBeVisible()
})
