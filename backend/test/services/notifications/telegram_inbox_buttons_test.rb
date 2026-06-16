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

    # Mensagens que são um gasto (têm botão tx:*), separadas do rodapé.
    def expense_messages
      @channel.sent.select { |m| m.dig(:reply_markup, :inline_keyboard, 0, 0, :callback_data)&.start_with?("tx:") }
    end

    test "envia uma mensagem por transação pendente, pro chat do workspace" do
      a = pending_tx
      b = pending_tx(original_description: "UBER", amount_cents: 2350)

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ a.id, b.id ], channel: @channel)

      assert_equal 2, expense_messages.size
      assert_equal [ -100777, -100777 ], expense_messages.map { |m| m[:chat_id] }
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

    test "cada gasto tem só Consolidar e Rejeitar; 'Abrir no app' vai no rodapé" do
      tx = pending_tx

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)

      rows = @channel.sent.first[:reply_markup][:inline_keyboard]
      assert_equal 1, rows.size # só Consolidar/Rejeitar — sem linha de link
      consolidar, rejeitar = rows[0]
      assert_equal "tx:consolidate:#{tx.id}", consolidar[:callback_data]
      assert_equal "tx:reject:#{tx.id}", rejeitar[:callback_data]
      assert rows.flatten.none? { |b| b[:url] }, "o gasto não deve ter link 'Abrir no app'"

      footer = @channel.sent.last
      abrir  = footer[:reply_markup][:inline_keyboard].last.first
      assert_equal "Abrir no app", abrir[:text]
      assert_equal "https://#{ENV.fetch('APP_HOST')}/inbox", abrir[:url]
    end

    test "ignora transações que não estão mais pendentes" do
      pendente    = pending_tx
      consolidada = pending_tx(status: "consolidated", consolidated_at: Time.current)

      TelegramInboxButtons.call(
        workspace: @workspace,
        transaction_ids: [ pendente.id, consolidada.id ],
        channel: @channel
      )

      assert_equal 1, expense_messages.size
    end

    test "callback_data cabe no limite de 64 bytes do Telegram" do
      tx = pending_tx
      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)

      @channel.sent.first[:reply_markup][:inline_keyboard][0].each do |btn|
        assert_operator btn[:callback_data].bytesize, :<=, 64
      end
    end

    # --- cap 7 + overflow (fluxo do sync) --------------------------------

    test "lote grande: manda só as 7 mais recentes + rodapé com overflow e link" do
      ids = (1..10).map { |i| pending_tx(occurred_at: Date.new(2026, 6, i)).id }

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: ids, channel: @channel)

      # 7 gastos + 1 rodapé = 8 mensagens.
      assert_equal 7, expense_messages.size
      assert_equal 8, @channel.sent.size

      footer = @channel.sent.last
      assert_match "Mais 3 gastos novos", footer[:text]
      link = footer[:reply_markup][:inline_keyboard].last.first
      assert_equal "Abrir no app", link[:text]
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

    test "exatamente 7: rodapé sem contagem de overflow, só o link" do
      ids = (1..7).map { |i| pending_tx(occurred_at: Date.new(2026, 6, i)).id }

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: ids, channel: @channel)

      assert_equal 7, expense_messages.size
      footer = @channel.sent.last
      assert_no_match(/mais \d+ gasto/i, footer[:text]) # sem overflow
      assert_equal "Abrir no app", footer[:reply_markup][:inline_keyboard].last.first[:text]
    end

    # --- push_pending (comando /pendentes + ver mais) --------------------

    test "push_pending manda as 7 pendentes mais recentes + botão ver mais quando há mais" do
      (1..10).each { |i| pending_tx(occurred_at: Date.new(2026, 6, i)) }

      TelegramInboxButtons.push_pending(workspace: @workspace, offset: 0, channel: @channel)

      assert_equal 7, expense_messages.size
      assert_equal 8, @channel.sent.size # 7 gastos + 1 rodapé
      footer = @channel.sent.last
      assert_match "Mostrando 7 de 10 pendentes", footer[:text]
      rows = footer[:reply_markup][:inline_keyboard]
      ver_mais = rows[0][0]
      assert_equal "Ver mais 7", ver_mais[:text]
      assert_equal "inbox:more:7", ver_mais[:callback_data]
      # "Abrir no app" embaixo do "Ver mais 7".
      assert_equal "Abrir no app", rows.last.first[:text]
    end

    test "push_pending com offset pagina os próximos e encerra sem ver mais" do
      (1..10).each { |i| pending_tx(occurred_at: Date.new(2026, 6, i)) }

      TelegramInboxButtons.push_pending(workspace: @workspace, offset: 7, channel: @channel)

      # restam 3 gastos → 3 + rodapé = 4, e o rodapé não tem "Ver mais".
      assert_equal 3, expense_messages.size
      footer = @channel.sent.last
      assert @channel.sent.none? { |m| m[:text].to_s.include?("Ver mais") }
      assert_equal "Abrir no app", footer[:reply_markup][:inline_keyboard].last.first[:text]
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
