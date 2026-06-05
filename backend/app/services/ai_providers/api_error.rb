module AiProviders
  # Erro de uma chamada ao provider de IA, classificado para feedback ao usuário.
  # `reason` é a categoria; `user_message` é a frase amigável PT-BR; `retryable?`
  # diz se vale a pena re-tentar (quota é permanente até recarga de crédito).
  class ApiError < StandardError
    REASONS = %i[quota rate_limit unavailable error].freeze

    USER_MESSAGES = {
      quota:       "O limite do serviço de IA foi atingido.",
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

    # Quota é permanente (créditos esgotados) — re-tentar só queima tempo.
    def retryable?
      reason != :quota
    end

    # Forma persistida no canal workspace.ai_last_error (e serializada à UI).
    # `message` é amigável; `detail` (técnico) fica só pra log/diagnóstico.
    def to_h
      { reason: reason.to_s, message: user_message, detail: message }
    end
  end
end
