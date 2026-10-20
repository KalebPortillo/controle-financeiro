import { test, expect } from '@playwright/test'
import { signIn, goto, seed } from './helpers'

/**
 * Gastos do mês: compras feitas no mês em cima; parcelas de compras de meses
 * anteriores embaixo, sob um cabeçalho com contagem e subtotal.
 */

test.use({ viewport: { width: 390, height: 844 }, hasTouch: true })

test('parcela de compra anterior vai pra seção de baixo, com a data da compra', async ({ page, context }) => {
  await signIn(context, { email: `gastos-sec-${Date.now()}@example.com`, name: 'Gastos Sec' })
  const { current_id, parcel_id } = await seed(context, 'gastos_sections')

  await goto(page, '/gastos')

  const order = page.locator('[data-testid^="gasto-row-"], [data-testid^="gastos-section-"]')
  await expect(order).toHaveCount(4)
  const testids = await order.evaluateAll((els) => els.map((el) => el.getAttribute('data-testid')))
  expect(testids).toEqual([
    'gastos-section-current', `gasto-row-${current_id}`, 'gastos-section-previous', `gasto-row-${parcel_id}`,
  ])
  await expect(page.getByTestId('gastos-section-previous')).toContainText('R$ 233,15')
  await expect(page.getByTestId(`purchase-date-${parcel_id}`)).toContainText('compra em')

  await page.screenshot({ path: 'test-results/gastos-sections-mobile.png' })
})
