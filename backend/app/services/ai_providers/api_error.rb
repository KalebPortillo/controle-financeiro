module AiProviders
  # Erro de uma chamada ao provider de IA, classificado para feedback ao usuário.
  # `reason` é a categoria; `user_message` é a frase amigável PT-BR; `retryable?`
  # diz se vale a pena re-tentar.
  # - quota: créditos pré-pagos esgotados (permanente até recarga).
  # - daily: limite DIÁRIO do free tier (volta no reset; re-tentar agora é inútil).
  # - rate_limit: limite por minuto (transitório — re-tentar com backoff resolve).
  # - unavailable: rede/5xx (transitório). error: demais.
  class ApiError < StandardError
    REASONS = %i[quota daily rate_limit unavailable error].freeze
    NON_RETRYABLE = %i[quota daily].freeze

    USER_MESSAGES = {
      quota:       "O limite do serviço de IA foi atingido.",
      daily:       "O limite diário da IA foi atingido. Tente novamente amanhã.",
      rate_limit:  "Muitas análises em pouco tempo. Tente de novo em instantes.",
      unavailable: "Serviço de IA indisponível no momento.",
      error:       "Não foi possível analisar com a IA."
    }.freeze

    attr_reader :reason

    def initialize(message = nil, reason: :error)
      super(message)
      @reason = REASONS.include?(reason) ? reason : :error
    end

    def user_message
      USER_MESSAGES[@reason]
    end

    # quota/daily não valem re-tentativa imediata (permanente / só volta amanhã).
    def retryable?
      !NON_RETRYABLE.include?(reason)
    end

    # Forma persistida no canal workspace.ai_last_error (e serializada à UI).
    # `message` é amigável; `detail` (técnico) fica só pra log/diagnóstico.
    def to_h
      { reason: reason.to_s, message: user_message, detail: message }
    end
  end
end
