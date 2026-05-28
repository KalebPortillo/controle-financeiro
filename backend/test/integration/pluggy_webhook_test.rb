require "test_helper"

# Webhook do Pluggy. Pluggy NÃO assina com HMAC — segurança é via header
# secreto (configurado ao registrar o webhook) + IP whitelist. Validamos o
# header X-Webhook-Secret contra PLUGGY_WEBHOOK_SECRET.
class PluggyWebhookTest < ActionDispatch::IntegrationTest
  SECRET = "test-webhook-secret".freeze

  def post_webhook(payload, secret: SECRET)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["X-Webhook-Secret"] = secret if secret
    post "/api/v1/webhooks/pluggy", params: payload.to_json, headers: headers
  end

  test "sem header secreto → 401 e não enfileira nada" do
    assert_no_enqueued_jobs do
      post_webhook({ event: "item/updated", itemId: "x" }, secret: nil)
    end
    assert_response :unauthorized
  end

  test "header secreto errado → 401" do
    post_webhook({ event: "item/updated", itemId: "x" }, secret: "wrong")
    assert_response :unauthorized
  end

  test "item/updated de item conhecido enfileira SyncJob" do
    conn = create(:bank_connection, external_connection_id: "item-known")
    assert_enqueued_with(job: BankConnections::SyncJob, args: [ conn.id ]) do
      post_webhook({ event: "item/updated", itemId: "item-known" })
    end
    assert_response :ok
  end

  test "transactions/created também enfileira sync" do
    conn = create(:bank_connection, external_connection_id: "item-tx")
    assert_enqueued_with(job: BankConnections::SyncJob, args: [ conn.id ]) do
      post_webhook({ event: "transactions/created", itemId: "item-tx" })
    end
    assert_response :ok
  end

  test "item/error marca a conexão como error (não enfileira sync)" do
    conn = create(:bank_connection, external_connection_id: "item-err", status: "connected")
    assert_no_enqueued_jobs do
      post_webhook({ event: "item/error", itemId: "item-err",
                     error: { message: "login falhou" } })
    end
    assert_response :ok
    assert_equal "error", conn.reload.status
  end

  test "item desconhecido → 200 (ack) mas sem efeito" do
    assert_no_enqueued_jobs do
      post_webhook({ event: "item/updated", itemId: "nao-existe" })
    end
    assert_response :ok
  end

  test "evento ignorado (ex.: connector/status_updated) → 200 sem efeito" do
    create(:bank_connection, external_connection_id: "item-z")
    assert_no_enqueued_jobs do
      post_webhook({ event: "connector/status_updated", itemId: "item-z" })
    end
    assert_response :ok
  end
end
