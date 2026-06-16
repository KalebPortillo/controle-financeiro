require "test_helper"

class BankConnections::EnsureWebhookTest < ActiveSupport::TestCase
  URL    = "https://wallet.example/api/v1/webhooks/pluggy".freeze
  SECRET = "s3cr3t".freeze

  # Provider fake: registra as criações e devolve uma lista de webhooks existentes.
  class FakeProvider
    attr_reader :created

    def initialize(existing = [])
      @existing = existing
      @created  = []
    end

    def list_webhooks
      @existing
    end

    def create_webhook(url:, event:, headers:)
      @created << { url: url, event: event, headers: headers }
      { id: "wh-#{event}", event: event, url: url }
    end
  end

  test "cria um webhook por evento quando nenhum existe, com o header secreto" do
    provider = FakeProvider.new([])

    created = BankConnections::EnsureWebhook.call(url: URL, secret: SECRET, provider: provider)

    assert_equal BankConnections::EnsureWebhook::EVENTS.sort, created.sort
    assert_equal BankConnections::EnsureWebhook::EVENTS.sort, provider.created.map { |w| w[:event] }.sort
    assert provider.created.all? { |w| w[:headers] == { "X-Webhook-Secret" => SECRET } }
    assert provider.created.all? { |w| w[:url] == URL }
  end

  test "é idempotente: não recria eventos já registrados na mesma url" do
    existing = [
      { id: "a", event: "item/updated",          url: URL },
      { id: "b", event: "transactions/created",   url: URL }
    ]
    provider = FakeProvider.new(existing)

    created = BankConnections::EnsureWebhook.call(url: URL, secret: SECRET, provider: provider)

    assert_equal %w[transactions/updated item/error].sort, created.sort
    assert_equal %w[transactions/updated item/error].sort, provider.created.map { |w| w[:event] }.sort
  end

  test "ignora webhooks de outra url ao decidir o que falta" do
    existing = [ { id: "x", event: "item/updated", url: "https://outro.app/webhook" } ]
    provider = FakeProvider.new(existing)

    created = BankConnections::EnsureWebhook.call(url: URL, secret: SECRET, provider: provider)

    assert_includes created, "item/updated" # a url nossa ainda não tinha
    assert_equal BankConnections::EnsureWebhook::EVENTS.sort, created.sort
  end

  test "nada a criar quando todos os eventos já existem" do
    existing = BankConnections::EnsureWebhook::EVENTS.map { |e| { id: e, event: e, url: URL } }
    provider = FakeProvider.new(existing)

    created = BankConnections::EnsureWebhook.call(url: URL, secret: SECRET, provider: provider)

    assert_empty created
    assert_empty provider.created
  end
end
