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

    # --- cap 7 + overflow (fluxo do sync) --------------------------------

    test "lote grande: manda só as 7 mais recentes + 1 mensagem de overflow com link" do
      ids = (1..10).map { |i| pending_tx(occurred_at: Date.new(2026, 6, i)).id }

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: ids, channel: @channel)

      # 7 com botões + 1 de overflow = 8 mensagens.
      assert_equal 8, @channel.sent.size
      buttoned = @channel.sent.first(7)
      assert buttoned.all? { |m| m[:reply_markup][:inline_keyboard][0][0][:text] == "Consolidar" }

      overflow = @channel.sent.last
      assert_match "Mais 3 gastos novos", overflow[:text]
      link = overflow[:reply_markup][:inline_keyboard][0][0]
      assert_equal "Abrir inbox", link[:text]
      assert_equal "https://#{ENV.fetch('APP_HOST')}/inbox", link[:url]
    end

    test "manda as 7 MAIS RECENTES (ordem por data desc)" do
      old = pending_tx(occurred_at: Date.new(2026, 1, 1), original_description: "ANTIGA")
      ids = (2..9).map { |i| pending_tx(occurred_at: Date.new(2026, 6, i)).id }

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: ids + [ old.id ], channel: @channel)

      # 9 ids → manda 7, a mais antiga fica de fora.
      sent_texts = @channel.sent.first(7).map { |m| m[:text] }
      assert sent_texts.none? { |t| t.include?("ANTIGA") }
    end

    test "exatamente 7: sem mensagem de overflow" do
      ids = (1..7).map { |i| pending_tx(occurred_at: Date.new(2026, 6, i)).id }

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: ids, channel: @channel)

      assert_equal 7, @channel.sent.size
      assert @channel.sent.none? { |m| m[:text].to_s.include?("gerencie no inbox") }
    end

    # --- push_pending (comando /pendentes + ver mais) --------------------

    test "push_pending manda as 7 pendentes mais recentes + botão ver mais quando há mais" do
      (1..10).each { |i| pending_tx(occurred_at: Date.new(2026, 6, i)) }

      TelegramInboxButtons.push_pending(workspace: @workspace, offset: 0, channel: @channel)

      assert_equal 8, @channel.sent.size # 7 botões + 1 "ver mais"
      more = @channel.sent.last
      assert_match "Mostrando 7 de 10 pendentes", more[:text]
      btn = more[:reply_markup][:inline_keyboard][0][0]
      assert_equal "Ver mais 7", btn[:text]
      assert_equal "inbox:more:7", btn[:callback_data]
    end

    test "push_pending com offset pagina os próximos e encerra sem botão" do
      (1..10).each { |i| pending_tx(occurred_at: Date.new(2026, 6, i)) }

      TelegramInboxButtons.push_pending(workspace: @workspace, offset: 7, channel: @channel)

      # restam 3 → 3 mensagens, sem "ver mais".
      assert_equal 3, @channel.sent.size
      assert @channel.sent.none? { |m| m[:text].to_s.include?("Ver mais") }
    end

    test "push_pending com inbox vazio avisa que não há pendentes" do
      TelegramInboxButtons.push_pending(workspace: @workspace, offset: 0, channel: @channel)

      assert_equal 1, @channel.sent.size
      assert_match(/nenhum gasto pendente/i, @channel.sent.first[:text])
    end

    test "push_pending sem Telegram vinculado é no-op" do
      @workspace.update!(telegram_chat_id: nil)
      pending_tx

      TelegramInboxButtons.push_pending(workspace: @workspace, channel: @channel)
      assert_empty @channel.sent
    end
  end
end
