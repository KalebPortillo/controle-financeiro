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

    # Mensagens que são um gasto ou compra parcelada (botão tx:* / grp:*), separadas do rodapé.
    def expense_messages
      @channel.sent.select { |m| m.dig(:reply_markup, :inline_keyboard, 0, 0, :callback_data)&.match?(/\A(tx|grp):/) }
    end

    # Parcelas pendentes de uma mesma compra (mesmo installment_group_id). A
    # parcela N cai N−1 meses depois da compra.
    def parcels(count:, total: count, group_id: SecureRandom.uuid, cents: 4630, purchase: Date.new(2026, 10, 8), **attrs)
      (1..count).map do |n|
        pending_tx(**{
          installment_group_id: group_id, installment_number: n, installment_total: total,
          amount_cents: cents, original_description: "AMAZON BR #{n}/#{total}",
          occurred_at: purchase >> (n - 1)
        }.merge(attrs))
      end
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

    test "gasto de cartão mostra os dígitos do cartão" do
      card = create(:account, workspace: @workspace, name: "Nubank", kind: "credit_card")
      tx = pending_tx(account: card, source_metadata: { "id" => "c1", "creditCardMetadata" => { "cardNumber" => "5190" } })

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)
      assert_match "Cartão ••5190", @channel.sent.first[:text]
    end

    test "transação de conta mostra a natureza (transferência/pagamento)" do
      tx = pending_tx(original_description: "Transferência enviada|Moacir")

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)
      text = @channel.sent.first[:text]
      assert_match "Transferência enviada", text
      assert_match "Nubank", text
    end

    test "mostra as tags aplicadas" do
      tx  = pending_tx
      tag = create(:tag, workspace: @workspace, name: "Mercado")
      tx.tags << tag

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)
      assert_match "Tags: Mercado", @channel.sent.first[:text]
    end

    test "sem tags aplicadas, mostra as sugeridas pela IA" do
      tx = pending_tx(ai_suggestion: { "tag_names" => [ "Delivery" ], "new_tags" => [ "iFood" ] })

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)
      text = @channel.sent.first[:text]
      assert_match "Sugestão:", text
      assert_match "Delivery", text
      assert_match "iFood", text
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
      rows = footer[:reply_markup][:inline_keyboard]
      # "Ver mais 7" (pagina os pendentes) + "Abrir no app".
      ver_mais = rows.first.first
      assert_equal "Ver mais 7", ver_mais[:text]
      assert_equal "inbox:more:7", ver_mais[:callback_data]
      link = rows.last.first
      assert_equal "Abrir no app", link[:text]
      assert_equal "https://#{ENV.fetch('APP_HOST')}/inbox", link[:url]
    end

    test "notificação do sync sem overflow não mostra 'Ver mais'" do
      ids = (1..3).map { |i| pending_tx(occurred_at: Date.new(2026, 6, i)).id }

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: ids, channel: @channel)

      footer = @channel.sent.last
      rows = footer[:reply_markup][:inline_keyboard]
      assert_equal 1, rows.size, "só 'Abrir no app', sem 'Ver mais'"
      assert_equal "Abrir no app", rows.first.first[:text]
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

    # --- retomada após falha de rede no meio do lote --------------------
    #
    # O envio é 1 request por gasto: um timeout no meio abortava o lote e os
    # gastos restantes nunca recebiam botão (não havia retry). Agora cada envio
    # é carimbado, então a re-execução manda só o que faltou.

    test "carimba telegram_notified_at em cada gasto enviado" do
      tx = pending_tx

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ tx.id ], channel: @channel)

      assert_not_nil tx.reload.telegram_notified_at
    end

    test "re-execução não reenvia gasto já notificado" do
      a = pending_tx(original_description: "PADARIA")
      b = pending_tx(original_description: "UBER")
      ids = [ a.id, b.id ]

      # 1ª rodada: manda os dois.
      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: ids, channel: @channel)
      assert_equal 2, expense_messages.size

      # 2ª rodada (retry do job): nada de gasto novo, sem duplicar.
      @channel.sent.clear
      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: ids, channel: @channel)
      assert_empty expense_messages
    end

    test "retoma o lote mandando só os gastos que faltaram" do
      enviado    = pending_tx(original_description: "PADARIA")
      pendentes  = 2.times.map { |i| pending_tx(original_description: "UBER #{i}") }
      enviado.update!(telegram_notified_at: Time.current)

      ids = [ enviado.id, *pendentes.map(&:id) ]
      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: ids, channel: @channel)

      textos = expense_messages.map { |m| m[:text] }
      assert_equal 2, textos.size
      assert textos.none? { |t| t.include?("PADARIA") }, "não deveria reenviar o já notificado"
    end

    test "timeout no meio do lote: o que passou fica carimbado, o resto não" do
      a = pending_tx(original_description: "PADARIA", occurred_at: Date.new(2026, 6, 10))
      b = pending_tx(original_description: "UBER",    occurred_at: Date.new(2026, 6, 9))

      # Canal que estoura no 2º envio, como um Net::ReadTimeout no meio do lote.
      flaky = Object.new
      def flaky.send_message(chat_id:, text:, reply_markup: nil)
        @n = (@n || 0) + 1
        raise NotificationChannels::TransientError, "timeout" if @n > 1
      end

      assert_raises(NotificationChannels::TransientError) do
        TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ a.id, b.id ], channel: flaky)
      end

      assert_not_nil a.reload.telegram_notified_at, "o que foi entregue fica carimbado"
      assert_nil     b.reload.telegram_notified_at, "o que falhou volta no retry"
    end

    test "push_pending reenvia mesmo já notificado (o usuário pediu a lista)" do
      tx = pending_tx
      tx.update!(telegram_notified_at: 1.day.ago)

      TelegramInboxButtons.push_pending(workspace: @workspace, channel: @channel)

      assert_equal 1, expense_messages.size
    end

    # --- compra parcelada: uma mensagem por compra (não por parcela) -----

    test "parcelas da mesma compra viram UMA mensagem com botões de grupo" do
      group = parcels(count: 12, improved_title: "Amazon Br")

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: group.map(&:id), channel: @channel)

      assert_equal 1, expense_messages.size
      msg = expense_messages.first
      assert_match "Amazon Br — 12x · R$ 555,60", msg[:text]
      assert_match "compra em 08/10", msg[:text]
      assert_match "12 parcelas no inbox (R$ 46,30 cada)", msg[:text]

      gid = group.first.installment_group_id
      row = msg[:reply_markup][:inline_keyboard].first
      assert_equal [ "Consolidar 12x", "Rejeitar 12x" ], row.map { |b| b[:text] }
      assert_equal [ "grp:consolidate:#{gid}", "grp:reject:#{gid}" ], row.map { |b| b[:callback_data] }
      assert row.all? { |b| b[:callback_data].bytesize <= 64 }
    end

    test "parcela sozinha no inbox usa o formato de compra, botões sem contagem" do
      parcel = parcels(count: 1, total: 4).first

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ parcel.id ], channel: @channel)

      msg = expense_messages.first
      assert_match "4x · R$ 46,30", msg[:text]
      assert_match "1 parcela no inbox", msg[:text]
      assert_equal [ "Consolidar", "Rejeitar" ], msg[:reply_markup][:inline_keyboard].first.map { |b| b[:text] }
      assert_match(/\Agrp:consolidate:/, msg[:reply_markup][:inline_keyboard].first.first[:callback_data])
    end

    test "valores diferentes entre parcelas: sem 'cada'" do
      gid = SecureRandom.uuid
      a = parcels(count: 1, total: 2, group_id: gid, cents: 5001).first
      b = pending_tx(installment_group_id: gid, installment_number: 2, installment_total: 2,
                     amount_cents: 4999, occurred_at: Date.new(2026, 11, 8))

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ a.id, b.id ], channel: @channel)

      text = expense_messages.first[:text]
      assert_match "2 parcelas no inbox", text
      assert_no_match(/cada/, text)
      assert_match "R$ 100,00", text
    end

    test "a mensagem do grupo conta todas as parcelas pendentes da compra, não só as do lote" do
      group = parcels(count: 3)

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: [ group.last.id ], channel: @channel)

      assert_equal 1, expense_messages.size
      assert_match "3 parcelas no inbox", expense_messages.first[:text]
    end

    test "limite de 7 conta compras, não parcelas" do
      group   = parcels(count: 12, purchase: Date.new(2026, 6, 20))
      singles = (1..7).map { |i| pending_tx(occurred_at: Date.new(2026, 6, i)) }

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: (group + singles).map(&:id), channel: @channel)

      # 8 itens (1 compra parcelada + 7 avulsos) → 7 mensagens + rodapé com 1 de overflow.
      assert_equal 7, expense_messages.size
      assert_match(/\Agrp:/, expense_messages.first[:reply_markup][:inline_keyboard].first.first[:callback_data])
      assert_match "Mais 1 gasto novo", @channel.sent.last[:text]
    end

    test "push_pending pagina por compra e informa o total em itens" do
      parcels(count: 10, purchase: Date.new(2026, 6, 20))
      (1..8).each { |i| pending_tx(occurred_at: Date.new(2026, 6, i)) }

      TelegramInboxButtons.push_pending(workspace: @workspace, offset: 0, channel: @channel)

      assert_equal 7, expense_messages.size
      assert_match "Mostrando 7 de 9 pendentes", @channel.sent.last[:text]
    end

    test "carimba todas as parcelas da compra e não reenvia no retry" do
      group = parcels(count: 3)

      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: group.map(&:id), channel: @channel)
      assert group.all? { |p| p.reload.telegram_notified_at.present? }

      @channel.sent.clear
      TelegramInboxButtons.call(workspace: @workspace, transaction_ids: group.map(&:id), channel: @channel)
      assert_empty expense_messages
    end
  end
end
