require "test_helper"

# RF17 — webhook do Telegram: recebe updates do bot e vincula o grupo do casal
# ao workspace via código do deep-link (/start <code>).
class TelegramWebhookTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = create(:workspace,
                        telegram_link_code: "valid-code-123",
                        telegram_link_code_expires_at: 10.minutes.from_now)
    # Confirmação de vínculo é best-effort via job; aqui só interessa o estado.
  end

  def post_update(body, secret: ENV.fetch("TELEGRAM_WEBHOOK_SECRET"))
    post "/api/v1/webhooks/telegram", params: body, as: :json,
         headers: { "X-Telegram-Bot-Api-Secret-Token" => secret }
  end

  def start_message(text, chat_id: -100555, title: "Casa")
    { message: { text: text, chat: { id: chat_id, type: "group", title: title } } }
  end

  test "secret errado → 401 sem efeito" do
    post_update(start_message("/start valid-code-123"), secret: "errado")
    assert_response :unauthorized
    assert_nil @workspace.reload.telegram_chat_id
  end

  test "/start <code> válido vincula o chat ao workspace" do
    post_update(start_message("/start valid-code-123"))
    assert_response :ok

    @workspace.reload
    assert_equal(-100555, @workspace.telegram_chat_id)
    assert_equal "Casa", @workspace.telegram_chat_title
    assert @workspace.telegram_linked_at.present?
    assert_nil @workspace.telegram_link_code # código é de uso único
  end

  test "/start@bot <code> (formato de grupo) também vincula" do
    post_update(start_message("/start@controle_financeiro_test_bot valid-code-123"))
    assert_response :ok
    assert_equal(-100555, @workspace.reload.telegram_chat_id)
  end

  test "código expirado → 200 sem efeito" do
    @workspace.update!(telegram_link_code_expires_at: 1.minute.ago)

    post_update(start_message("/start valid-code-123"))
    assert_response :ok
    assert_nil @workspace.reload.telegram_chat_id
  end

  test "código desconhecido → 200 sem efeito" do
    post_update(start_message("/start nao-existe"))
    assert_response :ok
    assert_nil @workspace.reload.telegram_chat_id
  end

  test "update sem message ou sem /start → 200 (ack silencioso)" do
    post_update({ edited_message: { text: "oi" } })
    assert_response :ok

    post_update(start_message("bom dia"))
    assert_response :ok
    assert_nil @workspace.reload.telegram_chat_id
  end

  test "vínculo dispara confirmação no grupo (best-effort)" do
    base = "https://api.telegram.org/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}"
    stub = stub_request(:post, "#{base}/sendMessage")
      .with(body: hash_including("chat_id" => -100555))
      .to_return(status: 200, body: { ok: true }.to_json)

    perform_enqueued_jobs do
      post_update(start_message("/start valid-code-123"))
    end
    assert_requested(stub)
  end

  # --- callback_query (botões de ação) ---

  def callback_update(data, chat_id:, secret: ENV.fetch("TELEGRAM_WEBHOOK_SECRET"))
    body = { callback_query: {
      id: "cb-1", data: data,
      message: { message_id: 7, text: "PADARIA — R$ 50,00", chat: { id: chat_id } }
    } }
    post "/api/v1/webhooks/telegram", params: body, as: :json,
         headers: { "X-Telegram-Bot-Api-Secret-Token" => secret }
  end

  test "callback_query com secret errado → 401, sem efeito" do
    ws = create(:workspace, telegram_chat_id: -100123, telegram_linked_at: Time.current)
    tx = create(:transaction, workspace: ws, account: create(:account, workspace: ws),
                              status: "pending", direction: "debit", amount_cents: 100,
                              original_description: "X")
    base = "https://api.telegram.org/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}"

    callback_update("tx:consolidate:#{tx.id}", chat_id: -100123, secret: "errado")
    assert_response :unauthorized
    assert_equal "pending", tx.reload.status
    assert_not_requested :post, "#{base}/answerCallbackQuery"
  end

  test "callback Consolidar do grupo vinculado consolida e responde (ack 200)" do
    ws = create(:workspace, telegram_chat_id: -100123, telegram_linked_at: Time.current)
    tx = create(:transaction, workspace: ws, account: create(:account, workspace: ws),
                              status: "pending", direction: "debit", amount_cents: 100,
                              original_description: "X")
    base = "https://api.telegram.org/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}"
    stub_request(:post, %r{#{Regexp.escape(base)}/(answerCallbackQuery|editMessageText)})
      .to_return(status: 200, body: { ok: true }.to_json)

    perform_enqueued_jobs do
      callback_update("tx:consolidate:#{tx.id}", chat_id: -100123)
    end

    assert_response :ok
    assert_equal "consolidated", tx.reload.status
    assert_requested :post, "#{base}/answerCallbackQuery"
  end
end
