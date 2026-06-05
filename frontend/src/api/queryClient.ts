import { QueryClient, MutationCache } from '@tanstack/react-query'
import { toast } from 'sonner'
import { errorFeedback } from './errorMessage'

/**
 * Feedback uniforme de erro: toda mutation que falhar dispara um toast amigável,
 * a menos que opte por silêncio (`meta: { silent: true }` — telas que já mostram
 * o erro inline, ex.: ImportarPage). Queries NÃO geram toast por padrão (evita
 * ruído de polling); erros assíncronos de IA aparecem via banner/card inline.
 */
export function notifyMutationError(
  error: unknown,
  mutation?: { meta?: Record<string, unknown> }
): void {
  if (mutation?.meta?.silent) return
  const fb = errorFeedback(error)
  if (fb) toast.error(fb.title, { description: fb.description })
}

export function createQueryClient(): QueryClient {
  return new QueryClient({
    mutationCache: new MutationCache({
      onError: (error, _vars, _ctx, mutation) => notifyMutationError(error, mutation),
    }),
    defaultOptions: {
      queries: {
        // Sem usuários reais ainda — retry agressivo causaria ruído em dev.
        retry: 1,
        staleTime: 30_000,
      },
    },
  })
}
