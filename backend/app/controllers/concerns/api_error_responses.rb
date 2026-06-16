module ApiErrorResponses
  extend ActiveSupport::Concern

  # Renderização canônica de erros — formato espelha contratos-api.md v1.1:
  #   { error: { code, message, details: [{ field, code, message }] } }
  #
  # Os handlers abaixo cobrem o caminho comum (validação de model e param
  # obrigatório ausente) pra todo controller que herda de ApplicationController,
  # sem rescue inline repetido. Ações que precisam de um `code` de domínio
  # específico (ex.: "invalid_transfer", "invalid_refund") mantêm o próprio
  # `rescue` local — ele captura antes do rescue_from e vence.
  included do
    rescue_from ActiveRecord::RecordInvalid do |error|
      render_validation_error(error.record)
    end

    # params.require ausente — não há record, então sem `details`.
    rescue_from ActionController::ParameterMissing do |error|
      render_validation_message(error.message)
    end
  end

  def render_validation_error(record)
    render json: {
      error: {
        code:    "validation_failed",
        message: record.errors.full_messages.to_sentence,
        details: record.errors.map { |e| { field: e.attribute, code: e.type.to_s, message: e.message } }
      }
    }, status: :unprocessable_entity
  end

  # Erro de validação sem record associado (ParameterMissing, Date.parse inválida).
  def render_validation_message(message, code: "validation_failed")
    render json: { error: { code: code, message: message } }, status: :unprocessable_entity
  end
end
