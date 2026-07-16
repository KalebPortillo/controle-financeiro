require "test_helper"

module Notifications
  # Digest de pendentes no Telegram (/pendentes e botão "ver mais"). O contrato
  # do JOB: delegar pro TelegramInboxButtons.push_pending com o offset e ser
  # best-effort (workspace apagado ou API fora → não explode a fila).
  class TelegramPendingDigestJobTest < ActiveJob::TestCase
    setup do
      @workspace = create(:workspace, telegram_chat_id: -100999, telegram_linked_at: Time.current)
      @base = "https://api.telegram.org/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}"
    end

    test "manda as pendentes com botões pro grupo vinculado" do
      account = create(:account, workspace: @workspace)
      create(:transaction, workspace: @workspace, account: account, status: "pending")

      stub = stub_request(:post, "#{@base}/sendMessage")
        .to_return(status: 200, body: { ok: true }.to_json)

      TelegramPendingDigestJob.perform_now(@workspace.id)
      # 1 mensagem por pendente + o rodapé com o total.
      assert_requested(stub, at_least_times: 2)
    end

    test "workspace sem chat vinculado → no-op" do
      @workspace.update!(telegram_chat_id: nil)

      TelegramPendingDigestJob.perform_now(@workspace.id)
      # Nenhum stub registrado: qualquer request HTTP estouraria (WebMock).
    end

    test "workspace apagado entre enqueue e perform → no-op (discard)" do
      assert_nothing_raised do
        TelegramPendingDigestJob.perform_now(SecureRandom.uuid)
      end
    end

    test "RateLimitError re-enfileira (retry_on)" do
      account = create(:account, workspace: @workspace)
      create(:transaction, workspace: @workspace, account: account, status: "pending")

      stub_request(:post, "#{@base}/sendMessage")
        .to_return(status: 429, body: { ok: false, parameters: { retry_after: 5 } }.to_json)

      assert_enqueued_with(job: TelegramPendingDigestJob) do
        TelegramPendingDigestJob.perform_now(@workspace.id)
      end
    end
  end
end
