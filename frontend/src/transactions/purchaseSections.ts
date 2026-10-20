import type { InboxItem } from './inboxItems'
import type { InboxTransaction } from './useInbox'

/**
 * Seções dos gastos consolidados do mês: as compras FEITAS no mês em cima e,
 * embaixo, as parcelas de compras de meses anteriores. Sem isso a parcela 4/6
 * de uma compra de 30/07 (faturada em 30/10) aparecia no topo de outubro.
 */

// Data da compra de um gasto: parcela usa o purchase_date (âncora retro-calculada
// no backend — Transactions::Installment.purchase_anchor); o resto, a data do
// extrato. Gasto avulso NÃO usa o purchaseDate do cartão: uma compra de 30/09
// que postou em 01/10 é do extrato de outubro e não é "parcela antiga".
export function purchaseDateOf(t: InboxTransaction): string {
  if (t.installment_total != null) return t.purchase_date ?? t.occurred_at
  return t.occurred_at
}

function mainTransaction(item: InboxItem): InboxTransaction {
  if (item.kind === 'single') return item.transaction
  if (item.kind === 'related') return item.anchor
  return item.representative
}

export function splitByPurchaseMonth(
  items: InboxItem[],
  period: string, // "YYYY-MM"
): { current: InboxItem[]; previous: InboxItem[] } {
  const current: InboxItem[] = []
  const previous: InboxItem[] = []
  for (const item of items) {
    const month = purchaseDateOf(mainTransaction(item)).slice(0, 7)
    ;(month < period ? previous : current).push(item)
  }
  // sort estável: empates mantêm a ordem que veio do backend.
  current.sort((a, b) => purchaseDateOf(mainTransaction(b)).localeCompare(purchaseDateOf(mainTransaction(a))))
  previous.sort((a, b) => mainTransaction(b).occurred_at.localeCompare(mainTransaction(a).occurred_at))
  return { current, previous }
}
