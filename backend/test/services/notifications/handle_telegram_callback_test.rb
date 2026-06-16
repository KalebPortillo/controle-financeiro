require "test_helper"

module Notifications
  class HandleTelegramCallbackTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    class FakeChannel
      attr_reader :answers, :edits

      def initialize
        @answers = []
        @edits   = []
      end

      def answer_callback_query(callback_query_id:, text: nil)
        @answers << { id: callback_query_id, text: text }
      end

      def edit_message_text(chat_id:, message_id:, text:, reply_markup: nil)
        @edits << { chat_id: chat_id, message_id: message_id, text: text }
      end
    end

    CHAT_ID = -100777

    setup do
      @workspace = create(:workspace, telegram_chat_id: CHAT_ID, telegram_linked_at: Time.current)
      @account   = create(:account, workspace: @workspace)
      @tx        = create(:transaction, workspace: @workspace, account: @account, status: "pending",
                                        direction: "debit", amount_cents: 5000,
                                        original_description: "PADARIA")
      @channel   = FakeChannel.new
    end

    def callback(data, chat_id: CHAT_ID, message_id: 42, text: "PADARIA — R$ 50,00")
      {
        id:      "cb-1",
        data:    data,
        message: { message_id: message_id, text: text, chat: { id: chat_id } }
      }
    end

    test "consolidate marca a transação como consolidated" do
      HandleTelegramCallback.call(callback_query: callback("tx:consolidate:#{@tx.id}"), channel: @channel)

      assert_equal "consolidated", @tx.reload.status
      assert @tx.consolidated_at.present?
    end

    test "reject marca como rejected" do
      HandleTelegramCallback.call(callback_query: callback("tx:reject:#{@tx.id}"), channel: @channel)

      assert_equal "rejected", @tx.reload.status
      assert @tx.rejected_at.present?
    end

    test "responde o toque e edita a mensagem removendo botões" do
      HandleTelegramCallback.call(callback_query: callback("tx:consolidate:#{@tx.id}"), channel: @channel)

      assert_equal "Consolidado", @channel.answers.first[:text]
      edit = @channel.edits.first
      assert_equal CHAT_ID, edit[:chat_id]
      assert_equal 42, edit[:message_id]
      assert_match "Consolidado", edit[:text]
    end

    test "toque numa transação já processada → 'já processada', sem mudar estado" do
      @tx.update!(status: "consolidated", consolidated_at: 1.hour.ago)

      HandleTelegramCallback.call(callback_query: callback("tx:reject:#{@tx.id}"), channel: @channel)

      assert_equal "consolidated", @tx.reload.status
      assert_match(/já processada/i, @channel.answers.first[:text])
    end

    test "chat não vinculado → ignora, sem mexer na transação" do
      HandleTelegramCallback.call(
        callback_query: callback("tx:consolidate:#{@tx.id}", chat_id: -999999),
        channel: @channel
      )

      assert_equal "pending", @tx.reload.status
      assert_match(/não vinculado/i, @channel.answers.first[:text])
    end

    test "transação de OUTRO workspace não é afetada (escopo)" do
      other_ws = create(:workspace, telegram_chat_id: -100888, telegram_linked_at: Time.current)
      other_tx = create(:transaction, workspace: other_ws,
                                      account: create(:account, workspace: other_ws),
                                      status: "pending", direction: "debit", amount_cents: 100,
                                      original_description: "X")

      # callback vem do chat do @workspace, mas tenta agir na tx do other_ws
      HandleTelegramCallback.call(
        callback_query: callback("tx:consolidate:#{other_tx.id}"),
        channel: @channel
      )

      assert_equal "pending", other_tx.reload.status
      assert_match(/não encontrada/i, @channel.answers.first[:text])
    end

    test "callback_data malformado → ação inválida" do
      HandleTelegramCallback.call(callback_query: callback("lixo"), channel: @channel)
      assert_match(/inválida/i, @channel.answers.first[:text])
    end

    test "inbox:more:<offset> dá ack e enfileira o digest paginado" do
      assert_enqueued_with(job: TelegramPendingDigestJob, args: [ @workspace.id, 7 ]) do
        HandleTelegramCallback.call(callback_query: callback("inbox:more:7"), channel: @channel)
      end
      # ack sem toast (não mexe em transação nem edita a mensagem).
      assert_equal 1, @channel.answers.size
      assert_empty @channel.edits
    end
  end
end
