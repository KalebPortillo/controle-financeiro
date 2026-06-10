module NotificationChannels
  # 429 do canal — transitório. `retry_after` vem da API (segundos) quando
  # disponível, pro job re-tentar com o espaçamento que o provedor pediu.
  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = "rate limited", retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end
end
