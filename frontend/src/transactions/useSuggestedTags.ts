import { tagsKey } from './useTags'
import { makeSuggestionHooks } from './makeSuggestionHooks'

// Tag sugerida pela IA (RF3/RF22), ainda não aceita. Catálogo separado das tags
// reais — vira Tag de verdade só quando aceita. Ver suggested_tags no backend.
export type SuggestedTag = {
  id: string
  name: string
  rationale: string | null
  coverage: number
  source: 'detected' | 'manual' | 'inbox'
  status: 'pending' | 'accepted' | 'dismissed'
}

export const suggestedTagsKey = ['suggested_tags'] as const

const hooks = makeSuggestionHooks<SuggestedTag, { id: string; transactionId?: string }>({
  resource: 'suggested_tags',
  responseKey: 'suggested_tags',
  queryKey: suggestedTagsKey,
  // Aceitar promove a Tag real (invalida tags) e, vindo do inbox com
  // transaction_id, a tag passa a estar aplicada (invalida transactions).
  invalidateOnAccept: [tagsKey, ['transactions']],
  acceptBody: (input) => (input.transactionId ? { transaction_id: input.transactionId } : undefined),
})

export const useSuggestedTags = hooks.useList
// Aceita a sugestão → cria a Tag real (ou reusa de mesmo nome) e marca accepted.
// Opcionalmente aplica a tag a uma transação (caminho do chip fantasma da inbox).
export const useAcceptSuggestedTag = hooks.useAccept
// Recusa a sugestão (status dismissed) — some da lista.
export const useDismissSuggestedTag = hooks.useDismiss
