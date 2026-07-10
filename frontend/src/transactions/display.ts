import type { InboxTransaction } from './useInbox'

// Helpers de exibição compartilhados pelas telas de transações (inbox, gastos,
// sheets). Fonte única — antes duplicados em cada componente.

// dd/mm a partir de uma data ISO (YYYY-MM-DD).
export function formatDayMonth(iso: string): string {
  const [, m, d] = iso.split('-')
  return `${d}/${m}`
}

// Valor com sinal por direção: débito negativo, crédito positivo.
export function signedCents(t: Pick<InboxTransaction, 'direction' | 'amount_cents'>): number {
  return t.direction === 'debit' ? -t.amount_cents : t.amount_cents
}

// Título a exibir: o melhorado (IA/usuário) ou, na falta, a descrição do banco.
export function displayTitle(t: Pick<InboxTransaction, 'improved_title' | 'original_description'>): string {
  return t.improved_title || t.original_description
}

// Título da ÂNCORA de um grupo. Normalmente é a própria compra; mas quando o
// grupo ancora numa cobrança de IOF (a compra não está na lista), o título
// genérico "IOF compra internacional" vira "IOF · <compra>" usando a compra
// vinculada (RF23, role origin) que o `related` carrega.
export function groupAnchorTitle(anchor: InboxTransaction): string {
  const iofOrigin = (anchor.related ?? []).find((r) => r.role === 'origin' && r.relation_type === 'iof')
  return iofOrigin ? `IOF · ${iofOrigin.title}` : displayTitle(anchor)
}
