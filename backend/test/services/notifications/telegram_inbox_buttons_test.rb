require "test_helper"

module Notifications
  class TelegramInboxButtonsTest < ActiveSupport::TestCase
    # Canal fake que captura as chamadas pra inspecionar texto + botões.
    class FakeChannel
      attr_reader :sent

      def initialize
        @sent = []
      end

      def send_message(chat_id:, text:, reply_markup: nil)
        @sent << { chat_id: chat_id, text: text, reply_markup: reply_markup }
      end
    end

    setup do
      @workspace = create(:workspace, telegram_chat_id: -100777, telegram_linked_at: Time.current)
      @account   = create(:account, workspace: @workspace, name: "Nubank")
      @channel   = FakeChannel.new
    end

    def pending_tx(**attrs)
      create(:transaction, **{
        workspace: @workspace, account: @account, status: "pending",
        direction: "debit", amount_cents: 5000,
        original_description: "PADARIA", occurred_at: Date.new(2026, 6, 9)
      }.merge(attrs))
    end

    test "envia uma mensagem por transação pendente, pro chat do workspace" do
      a = pending_tx
      b = pending_tx(original_description: "UBER", amount_cents: 2350)

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ a.id, b.id ], channel: @channel)

      assert_equal 2, @channel.sent.size
      assert_equal [ -100777, -100777 ], @channel.sent.map { |m| m[:chat_id] }
    end

    test "texto traz título, valor e conta" do
      tx = pending_tx(improved_title: "Padaria do Zé", amount_cents: 1234)

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)

      text = @channel.sent.first[:text]
      assert_match "Padaria do Zé", text
      assert_match "R$ 12,34", text
      assert_match "Nubank", text
      assert_match "09/06", text
    end

    test "usa original_description quando não há improved_title" do
      tx = pending_tx(improved_title: nil, original_description: "MERCADO X")

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)
      assert_match "MERCADO X", @channel.sent.first[:text]
    end

    test "inline keyboard tem Consolidar, Rejeitar e Abrir no app" do
      tx = pending_tx

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)

      rows = @channel.sent.first[:reply_markup][:inline_keyboard]
      consolidar, rejeitar = rows[0]
      assert_equal "Consolidar", consolidar[:text]
      assert_equal "tx:consolidate:#{tx.id}", consolidar[:callback_data]
      assert_equal "Rejeitar", rejeitar[:text]
      assert_equal "tx:reject:#{tx.id}", rejeitar[:callback_data]

      abrir = rows[1].first
      assert_equal "Abrir no app", abrir[:text]
      assert_equal "https://#{ENV.fetch('APP_HOST')}/inbox", abrir[:url]
    end

    test "ignora transações que não estão mais pendentes" do
      pendente   = pending_tx
      consolidada = pending_tx(status: "consolidated", consolidated_at: Time.current)

      TelegramInboxButtons.call(
        workspace: @workspace,
        transaction_ids: [ pendente.id, consolidada.id ],
        channel: @channel
      )

      assert_equal 1, @channel.sent.size
    end

    test "callback_data cabe no limite de 64 bytes do Telegram" do
      tx = pending_tx
      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)

      @channel.sent.first[:reply_markup][:inline_keyboard][0].each do |btn|
        assert_operator btn[:callback_data].bytesize, :<=, 64
      end
    end
  end
end
