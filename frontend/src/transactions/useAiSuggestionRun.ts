import { useEffect, useRef } from 'react'
import { toast } from 'sonner'

// A geração de sugestões é assíncrona (job no backend). A UI faz polling até as
// sugestões chegarem — mas a IA pode concluir SEM nada novo (e sem erro), então
// sem um prazo o "Sugerindo…" giraria pra sempre. Janela alinhada ao onboarding.
export const AI_SUGGESTION_DEADLINE_MS = 45_000

// Ao atualizar um toast de loading pelo mesmo id, o Sonner herda a duração
// Infinity dele — sem isto o toast de desfecho nunca sumiria.
const RESULT_TOAST_MS = 4_000

export type AiSuggestionMessages = {
  loading: string
  ready: (count: number) => string
  empty: string
}

type Options = {
  active: boolean
  count: number
  hasError: boolean
  onFinish: () => void
  messages: AiSuggestionMessages
  deadlineMs?: number
}

/**
 * Feedback explícito (toasts) de uma rodada de sugestão da IA, separado do
 * estado de loading (que o componente mantém, p/ não ciclar com a query):
 * loading ao iniciar → sucesso quando chegam N sugestões novas → aviso se a IA
 * não trouxe nada dentro do prazo. Chama `onFinish` nos três casos e no erro
 * (que já é mostrado por um Alert inline). O componente chama `start(baseline)`
 * no clique e cuida do estado `active`.
 */
export function useAiSuggestionRun(opts: Options) {
  const { active, count, hasError, onFinish, messages, deadlineMs = AI_SUGGESTION_DEADLINE_MS } = opts
  const baseline = useRef(0)
  const toastId = useRef<string | number | undefined>(undefined)

  // Resultado: novas sugestões chegaram, ou a IA falhou.
  useEffect(() => {
    if (!active) return
    if (hasError) {
      toast.dismiss(toastId.current)
      onFinish()
      return
    }
    const delta = count - baseline.current
    if (delta > 0) {
      toast.success(messages.ready(delta), { id: toastId.current, duration: RESULT_TOAST_MS })
      onFinish()
    }
    // onFinish/messages fora das deps: estáveis o bastante; re-rodar à toa é
    // inofensivo (guardado por `active`), o gatilho real é count/hasError.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active, count, hasError])

  // Prazo-limite: IA concluiu sem novidades — encerra com um aviso sóbrio.
  useEffect(() => {
    if (!active) return
    const t = setTimeout(() => {
      toast.message(messages.empty, { id: toastId.current, duration: RESULT_TOAST_MS })
      onFinish()
    }, deadlineMs)
    return () => clearTimeout(t)
    // Só re-armar quando `active` muda — incluir messages/deadline impediria o
    // timer de disparar (reset a cada render).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active])

  // Capturada no clique: a contagem de partida do alvo (o `count` observado
  // pode só refletir o alvo no próximo render).
  const start = (baselineCount: number) => {
    baseline.current = baselineCount
    toastId.current = toast.loading(messages.loading)
  }

  return { start }
}
