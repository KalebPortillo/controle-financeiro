import { useCallback } from 'react'
import { useLocation, useNavigate, useSearchParams } from 'react-router'

/**
 * Overlays (sheets, painéis) modelados como estado de URL via search params, pra
 * que o back do navegador / gesto de voltar feche o overlay — em vez de navegar
 * a rota por baixo. Cada abertura empurra uma entrada de histórico; o fechar pelo
 * X/backdrop consome essa entrada (back) ou, em deep-link/refresh, remove o param.
 *
 * Regras de histórico:
 *  - abrir (push)            → nova entrada; back fecha.
 *  - overlay → overlay irmão → push (back volta pro anterior; ex.: parcela↔grupo).
 *  - overlay → página cheia  → replace (não deixa overlay pendurado no histórico).
 */
export function useOverlay() {
  const [params] = useSearchParams()
  const navigate = useNavigate()
  const location = useLocation()
  const search = location.search

  const get = useCallback((key: string) => params.get(key), [params])

  // Empurra uma entrada de histórico mutando os search params (back fecha).
  const push = useCallback(
    (mutate: (p: URLSearchParams) => void) => {
      const next = new URLSearchParams(search)
      mutate(next)
      const s = next.toString()
      navigate({ search: s ? `?${s}` : '' })
    },
    [navigate, search],
  )

  // Fecha pelo X/backdrop: consome a entrada (back) quando há histórico interno
  // (location.key !== 'default'); senão (deep-link/refresh) remove os params via
  // replace pra não prender o usuário no overlay.
  const close = useCallback(
    (...keys: string[]) => {
      if (location.key !== 'default') {
        navigate(-1)
        return
      }
      const next = new URLSearchParams(search)
      keys.forEach((k) => next.delete(k))
      const s = next.toString()
      navigate({ search: s ? `?${s}` : '' }, { replace: true })
    },
    [navigate, location.key, search],
  )

  // Substitui o overlay atual por uma navegação de rota cheia (ex.: clicar numa
  // notificação) — sem deixar o overlay pendurado no histórico.
  const replaceWith = useCallback((to: string) => navigate(to, { replace: true }), [navigate])

  return { get, push, close, replaceWith }
}
