module BankAggregators
  # Resposta HTTP inesperada do provider (5xx, body malformado, etc.).
  # Pode ser transitório — o caller decide se retenta via job/scheduler.
  class UpstreamError < Error
    attr_reader :status, :body

    def initialize(status:, body:)
      @status = status
      @body   = body
      super("Pluggy upstream error: HTTP #{status} — #{body.to_s[0, 200]}")
    end
  end
end
