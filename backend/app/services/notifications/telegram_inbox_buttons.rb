module Notifications
  # Mensagens com botões inline por transação pendente (RF17) — Consolidar /
  # Rejeitar / Abrir no app. Telegram-only (o sininho in-app já cobre o resumo).
  #
  # Dois fluxos:
  #   - `call`         → disparado pelo Sync com os ids novos: manda as PAGE_SIZE
  #                      mais recentes; se o lote tiver mais, uma mensagem com
  #                      link pro inbox do app pra gerenciar o resto.
  #   - `push_pending` → comando /pendentes (e botão "ver mais"): manda PAGE_SIZE
  #                      pendentes a partir de `offset`; se sobrar, um botão que
  #                      pagina os próximos.
  module TelegramInboxButtons
    module_function

    PAGE_SIZE = 7

    def call(workspace:, transaction_ids:, channel: NotificationChannels::Telegram.new)
      chat_id = workspace.telegram_chat_id
      return if chat_id.blank?

      scope = workspace.transactions.where(id: transaction_ids, status: "pending")
      total = scope.count
      send_buttons(channel, chat_id, ordered(scope).limit(PAGE_SIZE).to_a)

      overflow = total - PAGE_SIZE
      send_overflow_link(channel, chat_id, overflow) if overflow.positive?
    end

    def push_pending(workspace:, offset: 0, channel: NotificationChannels::Telegram.new)
      chat_id = workspace.telegram_chat_id
      return if chat_id.blank?

      scope = workspace.transactions.where(status: "pending")
      total = scope.count
      page  = ordered(scope).offset(offset).limit(PAGE_SIZE).to_a

      if page.empty?
        text = offset.zero? ? "Nenhum gasto pendente no inbox" : "Sem mais gastos pendentes"
        return channel.send_message(chat_id: chat_id, text: text)
      end

      send_buttons(channel, chat_id, page)

      shown = offset + page.size
      send_more_button(channel, chat_id, shown, total) if total > shown
    end

    # --- helpers ----------------------------------------------------------

    # Mais recentes primeiro (a janela das PAGE_SIZE "últimas" pendentes).
    def ordered(scope)
      scope.includes(:account).order(occurred_at: :desc, created_at: :desc)
    end

    def send_buttons(channel, chat_id, txs)
      txs.each do |tx|
        channel.send_message(chat_id: chat_id, text: text_for(tx), reply_markup: keyboard_for(tx))
      end
    end

    def send_overflow_link(channel, chat_id, count)
      noun = count == 1 ? "gasto novo" : "gastos novos"
      channel.send_message(
        chat_id:      chat_id,
        text:         "Mais #{count} #{noun} — gerencie no inbox do app",
        reply_markup: { inline_keyboard: [ [ { text: "Abrir inbox", url: inbox_url } ] ] }
      )
    end

    def send_more_button(channel, chat_id, shown, total)
      channel.send_message(
        chat_id:      chat_id,
        text:         "Mostrando #{shown} de #{total} pendentes",
        reply_markup: { inline_keyboard: [ [ { text: "Ver mais #{PAGE_SIZE}", callback_data: "inbox:more:#{shown}" } ] ] }
      )
    end

    def text_for(tx)
      title = tx.improved_title.presence || tx.original_description
      "#{title} — #{Brl.format(tx.amount_cents)}\n" \
        "#{tx.account&.name} · #{tx.occurred_at.strftime('%d/%m')}"
    end

    def keyboard_for(tx)
      {
        inline_keyboard: [
          [
            { text: "Consolidar", callback_data: "tx:consolidate:#{tx.id}" },
            { text: "Rejeitar",   callback_data: "tx:reject:#{tx.id}" }
          ],
          [ { text: "Abrir no app", url: inbox_url } ]
        ]
      }
    end

    def inbox_url
      "https://#{ENV.fetch('APP_HOST')}/inbox"
    end
  end
end
