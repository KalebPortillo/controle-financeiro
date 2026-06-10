require "test_helper"

module Notifications
  class TelegramDeliveryJobTest < ActiveJob::TestCase
    setup do
      @workspace = create(:workspace, telegram_chat_id: -100999, telegram_linked_at: Time.current)
      @notification = create(:notification, workspace: @workspace, kind: "inbox_new",
                                            payload: { "count" => 2 })
      @base = "https://api.telegram.org/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}"
    end

    test "envia a mensagem renderizada pro chat vinculado" do
      stub = stub_request(:post, "#{@base}/sendMessage")
        .with(body: hash_including(
          "chat_id" => -100999,
          "text"    => "Sincronização concluída: 2 novos gastos aguardando revisão na inbox."
        ))
        .to_return(status: 200, body: { ok: true }.to_json)

      TelegramDeliveryJob.perform_now(@notification.id)
      assert_requested(stub)
    end

    test "workspace desvinculado entre enqueue e perform → no-op" do
      @workspace.update!(telegram_chat_id: nil)

      TelegramDeliveryJob.perform_now(@notification.id)
      # Nenhum stub registrado: qualquer request HTTP estouraria (WebMock).
    end

    test "notificação apagada → no-op (discard)" do
      assert_nothing_raised do
        TelegramDeliveryJob.perform_now(SecureRandom.uuid)
      end
    end

    test "ApiError (chat not found) não re-tenta" do
      stub_request(:post, "#{@base}/sendMessage")
        .to_return(status: 400, body: { ok: false, description: "chat not found" }.to_json)

      assert_nothing_raised do
        TelegramDeliveryJob.perform_now(@notification.id)
      end
    end

    test "RateLimitError re-enfileira (retry_on)" do
      stub_request(:post, "#{@base}/sendMessage")
        .to_return(status: 429, body: { ok: false, parameters: { retry_after: 5 } }.to_json)

      assert_enqueued_with(job: TelegramDeliveryJob) do
        TelegramDeliveryJob.perform_now(@notification.id)
      end
    end
  end
end
