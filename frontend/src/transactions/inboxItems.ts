import type { InboxTransaction } from './useInbox'

// Item da lista do inbox: ou um gasto avulso, ou um parcelamento agregado
// (todas as parcelas presentes do mesmo installment_group_id num único item).
export type InboxItem =
  | { kind: 'single'; transaction: InboxTransaction }
  | {
      kind: 'installment'
      groupId: string
      parcels: InboxTransaction[]
      total: number
      representative: InboxTransaction
      // Data da COMPRA do parcelamento (purchase_date; fallback: 1ª parcela).
      purchaseDate: string
    }

function isInstallment(t: InboxTransaction): boolean {
  return t.installment_total != null && t.installment_group_id != null
}

// Data que posiciona o item na lista: avulso = data do gasto; parcelamento =
// data da compra. Ambas YYYY-MM-DD, então ordenam lexicograficamente.
export function itemDate(item: InboxItem): string {
  return item.kind === 'single' ? item.transaction.occurred_at : item.purchaseDate
}

/**
 * Agrega as parcelas de cada parcelamento (mesmo installment_group_id) num item
 * único, preservando a ordem da lista (o grupo ocupa a posição da 1ª parcela que
 * aparece). `total` = soma das parcelas PRESENTES; `representative` = a parcela
 * com título (ou a de menor número) — usada pro título/detalhe do grupo.
 */
export function buildInboxItems(transactions: InboxTransaction[]): InboxItem[] {
  const items: InboxItem[] = []
  const groupIndex = new Map<string, number>() // group_id → posição em `items`

  for (const t of transactions) {
    if (!isInstallment(t)) {
      items.push({ kind: 'single', transaction: t })
      continue
    }

    const groupId = t.installment_group_id as string
    const at = groupIndex.get(groupId)
    if (at == null) {
      groupIndex.set(groupId, items.length)
      items.push({
        kind: 'installment',
        groupId,
        parcels: [t],
        total: t.amount_cents,
        representative: t,
        purchaseDate: t.occurred_at, // recomputado abaixo
      })
    } else {
      const item = items[at]
      if (item.kind !== 'installment') continue
      item.parcels.push(t)
      item.total += t.amount_cents
    }
  }

  // Por grupo: ordena parcelas por número, escolhe o representante (com título
  // primeiro) e fixa a data da compra (purchase_date; fallback = 1ª parcela).
  for (const item of items) {
    if (item.kind !== 'installment') continue
    item.parcels.sort((a, b) => (a.installment_number ?? 0) - (b.installment_number ?? 0))
    item.representative = item.parcels.find((p) => p.improved_title) ?? item.parcels[0]
    item.purchaseDate =
      item.representative.purchase_date ??
      item.parcels.reduce((min, p) => (p.occurred_at < min ? p.occurred_at : min), item.parcels[0].occurred_at)
  }

  // Ordena a lista por data desc (gasto = occurred_at; parcelamento = data da
  // compra), pra o parcelamento não flutuar pra posição da sua parcela mais
  // recente. Empate mantém a ordem que veio do backend (occurred_at, created_at).
  return items.sort((a, b) => itemDate(b).localeCompare(itemDate(a)))
}
