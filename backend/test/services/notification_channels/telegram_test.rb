require "test_helper"

module NotificationChannels
  class TelegramTest < ActiveSupport::TestCase
    setup do
      @client = Telegram.new(bot_token: "test-telegram-bot-token")
      @base   = "https://api.telegram.org/bottest-telegram-bot-token"
    end

    test "send_message posta chat_id e text" do
      stub = stub_request(:post, "#{@base}/sendMessage")
        .with(body: hash_including("chat_id" => -100123, "text" => "olá"))
        .to_return(status: 200, body: { ok: true, result: { message_id: 1 } }.to_json)

      @client.send_message(chat_id: -100123, text: "olá")
      assert_requested(stub)
    end

    test "send_message inclui reply_markup quando passado" do
      markup = { inline_keyboard: [ [ { text: "Consolidar", callback_data: "tx:consolidate:abc" } ] ] }
      stub = stub_request(:post, "#{@base}/sendMessage")
        .with(body: hash_including("chat_id" => -1, "text" => "x", "reply_markup" => {
          "inline_keyboard" => [ [ { "text" => "Consolidar", "callback_data" => "tx:consolidate:abc" } ] ]
        }))
        .to_return(status: 200, body: { ok: true }.to_json)

      @client.send_message(chat_id: -1, text: "x", reply_markup: markup)
      assert_requested(stub)
    end

    test "send_message sem reply_markup não inclui a chave" do
      stub = stub_request(:post, "#{@base}/sendMessage")
        .with { |req| !JSON.parse(req.body).key?("reply_markup") }
        .to_return(status: 200, body: { ok: true }.to_json)

      @client.send_message(chat_id: -1, text: "x")
      assert_requested(stub)
    end

    test "answer_callback_query responde o toque" do
      stub = stub_request(:post, "#{@base}/answerCallbackQuery")
        .with(body: hash_including("callback_query_id" => "cb1", "text" => "Consolidado"))
        .to_return(status: 200, body: { ok: true }.to_json)

      @client.answer_callback_query(callback_query_id: "cb1", text: "Consolidado")
      assert_requested(stub)
    end

    test "edit_message_text troca a mensagem e remove o teclado" do
      stub = stub_request(:post, "#{@base}/editMessageText")
        .with(body: hash_including("chat_id" => -1, "message_id" => 42, "text" => "Padaria — Consolidado"))
        .to_return(status: 200, body: { ok: true }.to_json)

      @client.edit_message_text(chat_id: -1, message_id: 42, text: "Padaria — Consolidado")
      assert_requested(stub)
    end

    test "4xx vira ApiError com a description da API" do
      stub_request(:post, "#{@base}/sendMessage")
        .to_return(status: 400, body: { ok: false, description: "Bad Request: chat not found" }.to_json)

      error = assert_raises(ApiError) do
        @client.send_message(chat_id: 1, text: "x")
      end
      assert_match(/chat not found/, error.message)
    end

    test "429 vira RateLimitError com retry_after" do
      stub_request(:post, "#{@base}/sendMessage")
        .to_return(status: 429, body: {
          ok: false, description: "Too Many Requests",
          parameters: { retry_after: 7 }
        }.to_json)

      error = assert_raises(RateLimitError) do
        @client.send_message(chat_id: 1, text: "x")
      end
      assert_equal 7, error.retry_after
    end

    test "5xx vira Error genérico" do
      stub_request(:post, "#{@base}/sendMessage").to_return(status: 502, body: "bad gateway")

      assert_raises(NotificationChannels::Error) do
        @client.send_message(chat_id: 1, text: "x")
      end
    end

    test "set_webhook envia url, secret_token e aceita message + callback_query" do
      stub = stub_request(:post, "#{@base}/setWebhook")
        .with(body: hash_including(
          "url" => "https://app.example/api/v1/webhooks/telegram",
          "secret_token" => "s3cret",
          "allowed_updates" => [ "message", "callback_query" ]
        ))
        .to_return(status: 200, body: { ok: true, result: true }.to_json)

      @client.set_webhook(url: "https://app.example/api/v1/webhooks/telegram", secret_token: "s3cret")
      assert_requested(stub)
    end
  end
end
