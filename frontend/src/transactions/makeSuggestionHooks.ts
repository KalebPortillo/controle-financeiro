import {
  useMutation,
  useQuery,
  useQueryClient,
  type QueryKey,
} from '@tanstack/react-query'
import { apiFetch } from '../api/client'

// Fábrica dos hooks de um catálogo de sugestões da IA (suggested_tags /
// suggested_categories): list (com poll opcional enquanto vazio), accept e
// dismiss compartilham toda a estrutura — só mudam o recurso, a query key, as
// keys a invalidar e o corpo do accept. Centraliza isso pra não duplicar.
export function makeSuggestionHooks<TItem, TAcceptInput extends { id: string }>(config: {
  resource: string // ex.: 'suggested_tags'
  responseKey: string // chave raiz do JSON do index, ex.: 'suggested_tags'
  queryKey: QueryKey
  invalidateOnAccept: QueryKey[] // além da própria queryKey
  acceptBody?: (input: TAcceptInput) => unknown
}) {
  const { resource, responseKey, queryKey, invalidateOnAccept, acceptBody } = config

  function useList({ pollWhileEmpty = false } = {}) {
    return useQuery({
      queryKey,
      queryFn: () =>
        apiFetch<Record<string, TItem[]>>(`/api/v1/${resource}`).then((r) => r[responseKey]),
      refetchInterval: (query) =>
        pollWhileEmpty && ((query.state.data as TItem[] | undefined)?.length ?? 0) === 0
          ? 3000
          : false,
    })
  }

  function useAccept() {
    const qc = useQueryClient()
    return useMutation({
      mutationFn: (input: TAcceptInput) =>
        apiFetch(`/api/v1/${resource}/${input.id}/accept`, {
          method: 'POST',
          body: acceptBody?.(input),
        }),
      onSuccess: () => {
        qc.invalidateQueries({ queryKey })
        invalidateOnAccept.forEach((k) => qc.invalidateQueries({ queryKey: k }))
      },
    })
  }

  function useDismiss() {
    const qc = useQueryClient()
    return useMutation({
      mutationFn: (id: string) => apiFetch(`/api/v1/${resource}/${id}`, { method: 'DELETE' }),
      onSuccess: () => qc.invalidateQueries({ queryKey }),
    })
  }

  return { useList, useAccept, useDismiss }
}
