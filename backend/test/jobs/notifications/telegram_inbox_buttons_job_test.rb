require "test_helper"

module Notifications
  class TelegramInboxButtonsJobTest < ActiveJob::TestCase
    setup do
      @workspace = create(:workspace, telegram_chat_id: -100777, telegram_linked_at: Time.current)
      @account   = create(:account, workspace: @workspace)
      @tx        = create(:transaction, workspace: @workspace, account: @account, status: "pending",
                                        direction: "debit", amount_cents: 5000, ai_status: "analyzed",
                                        original_description: "PADARIA", occurred_at: Date.new(2026, 6, 9))
      @base      = "https://api.telegram.org/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}"
    end

    test "aguarda a sugestão da IA: com tx ainda em queued, reagenda e não manda" do
      @tx.update!(ai_status: "queued")
      # Sem stub HTTP: se tentasse mandar agora, o WebMock estouraria.
      assert_enqueued_with(job: TelegramInboxButtonsJob) do
        TelegramInboxButtonsJob.perform_now(@workspace.id, [ @tx.id ])
      end
    end

    test "manda assim que a IA analisa (tx sai de queued)" do
      @tx.update!(ai_status: "analyzed")
      stub = stub_request(:post, "#{@base}/sendMessage")
        .to_return(status: 200, body: { ok: true }.to_json)

      assert_no_enqueued_jobs(only: TelegramInboxButtonsJob) do
        TelegramInboxButtonsJob.perform_now(@workspace.id, [ @tx.id ])
      end
      assert_requested(stub, at_least_times: 1)
    end

    test "failsafe: passado o teto de espera, manda mesmo com a IA ainda em queued" do
      @tx.update!(ai_status: "queued")
      stub = stub_request(:post, "#{@base}/sendMessage")
        .to_return(status: 200, body: { ok: true }.to_json)

      TelegramInboxButtonsJob.perform_now(@workspace.id, [ @tx.id ],
                                          TelegramInboxButtonsJob::MAX_WAIT_SECONDS)
      assert_requested(stub, at_least_times: 1)
    end

    test "envia a mensagem com botões pro chat vinculado" do
      stub = stub_request(:post, "#{@base}/sendMessage")
        .with(body: hash_including("chat_id" => -100777))
        .to_return(status: 200, body: { ok: true }.to_json)

      TelegramInboxButtonsJob.perform_now(@workspace.id, [ @tx.id ])
      assert_requested(stub, at_least_times: 1) # gasto + rodapé
    end

    test "workspace desvinculado entre enqueue e perform → no-op" do
      @workspace.update!(telegram_chat_id: nil)
      # Nenhum stub: qualquer request HTTP estouraria no WebMock.
      assert_nothing_raised { TelegramInboxButtonsJob.perform_now(@workspace.id, [ @tx.id ]) }
    end

    test "workspace inexistente → discard, sem erro" do
      assert_nothing_raised { TelegramInboxButtonsJob.perform_now(SecureRandom.uuid, [ @tx.id ]) }
    end
  end
end
