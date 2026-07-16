module OriginVerification
  extend ActiveSupport::Concern

  # Defesa em profundidade contra CSRF: a sessão é cookie SameSite=Lax (a
  # primeira camada), mas aqui rejeitamos qualquer request MUTANTE cujo header
  # Origin exista e venha de outro HOST. Requests máquina→máquina (webhooks
  # Pluggy/Telegram) não mandam Origin → passam; browser cross-site manda o
  # Origin do atacante → 403.
  #
  # Compara só o host (não scheme/porta): em dev/E2E o proxy do Vite reescreve
  # a porta (browser em :5173, Rails em :3000) e a comparação estrita rejeitaria
  # tudo. Atacante servindo em outra PORTA do mesmo host não é vetor realista.
  MUTATING_METHODS = %w[POST PUT PATCH DELETE].freeze

  included do
    before_action :verify_request_origin
  end

  private

  def verify_request_origin
    return unless MUTATING_METHODS.include?(request.request_method)

    origin = request.headers["Origin"].to_s
    return if origin.blank?
    return if origin_host(origin) == request.host

    render json: {
      error: { code: "origin_mismatch", message: "Request origin does not match this host." }
    }, status: :forbidden
  end

  # Host do header Origin; nil em valor malformado ou "null" (sandbox) → 403.
  def origin_host(origin)
    URI.parse(origin).host
  rescue URI::InvalidURIError
    nil
  end
end
