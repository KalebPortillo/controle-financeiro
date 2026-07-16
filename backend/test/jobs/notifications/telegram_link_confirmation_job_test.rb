require "test_helper"

module Notifications
  # Boas-vindas no grupo recém-vinculado (RF17). Best-effort: falha de API ou
  # workspace/vínculo sumido não pode derrubar o fluxo de vínculo.
  class TelegramLinkConfirmationJobTest < ActiveJob::TestCase
    setup do
      @workspace = create(:workspace, name: "Casa", telegram_chat_id: -100999,
                                      telegram_linked_at: Time.current)
      @base = "https://api.telegram.org/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}"
    end

    test "manda a mensagem de boas-vindas com o nome do workspace" do
      stub = stub_request(:post, "#{@base}/sendMessage")
        .with { |req| body = JSON.parse(req.body); body["chat_id"] == -100999 && body["text"].include?("Casa") }
        .to_return(status: 200, body: { ok: true }.to_json)

      TelegramLinkConfirmationJob.perform_now(@workspace.id)
      assert_requested(stub)
    end

    test "workspace desvinculado entre enqueue e perform → no-op" do
      @workspace.update!(telegram_chat_id: nil)

      TelegramLinkConfirmationJob.perform_now(@workspace.id)
      # Nenhum stub registrado: qualquer request HTTP estouraria (WebMock).
    end

    test "workspace apagado entre enqueue e perform → no-op (discard)" do
      assert_nothing_raised do
        TelegramLinkConfirmationJob.perform_now(SecureRandom.uuid)
      end
    end

    test "erro da API do Telegram não re-tenta (discard, best-effort)" do
      stub_request(:post, "#{@base}/sendMessage")
        .to_return(status: 400, body: { ok: false, description: "chat not found" }.to_json)

      assert_nothing_raised do
        TelegramLinkConfirmationJob.perform_now(@workspace.id)
      end
    end
  end
end
