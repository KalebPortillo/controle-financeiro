import { ApiError, UnauthorizedError } from './client'

export type ErrorFeedback = { title: string; description?: string }

/**
 * Mapeia qualquer erro lançado por uma chamada de API para um feedback amigável
 * em PT-BR (camada uniforme de erro). "Amigável + motivo": mostra a categoria
 * legível (sem conexão, limite atingido, erro do servidor…), nunca o corpo cru.
 * Retorna `null` quando não se deve mostrar feedback (ex.: 401 — o fluxo de auth
 * já redireciona).
 */
export function errorFeedback(error: unknown): ErrorFeedback | null {
  // 401 → o RequireAuth/useSession já trata o redirect; sem toast.
  if (error instanceof UnauthorizedError) return null

  if (error instanceof ApiError) {
    const { status, message } = error
    if (status === 429) {
      return { title: 'Limite atingido', description: 'Tente novamente em instantes.' }
    }
    if (status >= 500) {
      return { title: 'Erro no servidor', description: 'Tente de novo em um momento.' }
    }
    if (status === 403) {
      return { title: 'Sem permissão', description: message || 'Você não tem acesso a isso.' }
    }
    if (status === 404) {
      return { title: 'Não encontrado', description: message || undefined }
    }
    if (status === 422) {
      // Validação: o backend já manda uma mensagem amigável.
      return { title: 'Confira os dados', description: message || undefined }
    }
    return { title: 'Não foi possível concluir', description: message || undefined }
  }

  // fetch que rejeita (rede caiu, DNS, CORS) vira TypeError — sem `response`.
  if (error instanceof TypeError) {
    return { title: 'Sem conexão', description: 'Verifique sua internet e tente de novo.' }
  }

  return { title: 'Algo deu errado', description: 'Tente de novo em um momento.' }
}
