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
