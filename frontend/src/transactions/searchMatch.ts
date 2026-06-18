import type { InboxTransaction } from './useInbox'

// Acento-insensível e caixa-insensível, espelhando a busca server-side (Fase 1:
// unaccent + substring). Usado na inbox, que filtra client-side o conjunto já
// carregado (preserva o cache otimista/tempo real atrelado ao inboxKey).
export function normalizeForSearch(value: string): string {
  return value.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase()
}

// Casa por substring no título melhorado, na descrição original do banco ou em
// algum nome de tag. Query vazia casa com tudo (sem filtro).
export function transactionMatchesQuery(t: InboxTransaction, query: string): boolean {
  const needle = normalizeForSearch(query.trim())
  if (!needle) return true
  const haystacks = [t.improved_title ?? '', t.original_description, ...t.tags.map((tag) => tag.name)]
  return haystacks.some((h) => normalizeForSearch(h).includes(needle))
}
