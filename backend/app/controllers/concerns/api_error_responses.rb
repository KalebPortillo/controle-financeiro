module ApiErrorResponses
  extend ActiveSupport::Concern

  # Renderização canônica de erros — formato espelha contratos-api.md v1.1:
  #   { error: { code, message, details: [{ field, code, message }] } }
  #
  # Manter ApplicationController fino: outros tipos de erro (not_found,
  # forbidden) entram aqui se passarem a se repetir entre controllers.

  def render_validation_error(record)
    render json: {
      error: {
        code:    "validation_failed",
        message: record.errors.full_messages.to_sentence,
        details: record.errors.map { |e| { field: e.attribute, code: e.type.to_s, message: e.message } }
      }
    }, status: :unprocessable_entity
  end
end
