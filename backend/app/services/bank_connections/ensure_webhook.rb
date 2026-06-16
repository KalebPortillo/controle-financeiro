module BankConnections
  # Registra (idempotente) os webhooks do Pluggy apontando pro nosso endpoint
  # `POST /api/v1/webhooks/pluggy`. Sem isso o Pluggy nunca empurra eventos e o
  # inbox só atualiza no sync manual/periódico (RF1/RF21).
  #
  # O Pluggy aceita UM evento por webhook; registramos um por evento que nos
  # interessa, cada um com um `headers` que ele reenvia em toda chamada — é onde
  # vai o X-Webhook-Secret que `WebhooksController#verify_webhook_secret` valida.
  #
  # Idempotente: lista os webhooks existentes e cria só os (url, event) que
  # faltam — seguro pra rodar a cada deploy. `provider` injetável (fake em teste).
  class EnsureWebhook
    # Espelha SYNC_EVENTS + ERROR_EVENTS de WebhooksController.
    EVENTS = %w[item/updated transactions/created transactions/updated item/error].freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(url:, secret:, provider: default_provider, events: EVENTS)
      @url      = url
      @secret   = secret
      @provider = provider
      @events   = events
    end

    # Devolve os eventos efetivamente criados (vazio = já estava tudo registrado).
    def call
      existing = @provider.list_webhooks
                          .select { |w| w[:url] == @url }
                          .map    { |w| w[:event] }

      @events.reject { |event| existing.include?(event) }.each do |event|
        @provider.create_webhook(url: @url, event: event, headers: { "X-Webhook-Secret" => @secret })
      end
    end

    private

    def default_provider
      BankAggregators::Pluggy.new(
        client_id:     ENV.fetch("PLUGGY_CLIENT_ID"),
        client_secret: ENV.fetch("PLUGGY_CLIENT_SECRET")
      )
    end
  end
end
