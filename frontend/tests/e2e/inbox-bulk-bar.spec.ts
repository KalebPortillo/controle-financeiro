import { test, expect } from '@playwright/test'
import { signIn, goto, seed } from './helpers'

/**
 * Barra de ações em massa do inbox fica fixa no rodapé da janela: dá pra
 * selecionar no meio de uma lista longa e agir sem rolar até o fim. Valida no
 * viewport de celular (uso principal), onde a barra fica acima da bottom nav.
 */

test.use({ viewport: { width: 390, height: 844 }, hasTouch: true })

test('barra de ações visível no meio da lista e acima da bottom nav', async ({ page, context }) => {
  await signIn(context, { email: `bulk-bar-${Date.now()}@example.com`, name: 'Bulk Bar' })
  const { transaction_ids } = await seed<{ transaction_ids: string[] }>(context, 'long_inbox')
  const [first, middle] = [transaction_ids[0], transaction_ids[15]]

  await goto(page, '/inbox')
  await page.getByTestId(`select-${first}`).click()

  // Rola até um gasto do meio e seleciona — a barra continua na tela.
  await page.getByTestId(`select-${middle}`).scrollIntoViewIfNeeded()
  await page.getByTestId(`select-${middle}`).click()

  const bar = page.getByTestId('bulk-bar')
  await expect(bar).toBeInViewport()
  await expect(page.getByTestId('bulk-accept')).toHaveText('Aceitar (2)')

  // Não fica atrás da bottom nav: o rodapé da barra está acima do topo da nav.
  const barBox = await bar.boundingBox()
  const navBox = await page.locator('nav.fixed').boundingBox()
  expect(barBox!.y + barBox!.height).toBeLessThanOrEqual(navBox!.y)

  await page.screenshot({ path: 'test-results/inbox-bulk-bar-mobile.png' })

  await page.getByTestId('bulk-accept').click()
  await expect(page.getByTestId(`inbox-row-${first}`)).toHaveCount(0)
  await expect(page.getByTestId(`inbox-row-${middle}`)).toHaveCount(0)
  await expect(bar).toHaveCount(0)
})
