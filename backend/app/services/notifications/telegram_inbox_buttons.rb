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

      scope  = workspace.transactions.where(id: transaction_ids, status: "pending")
      recent = ordered(scope).limit(PAGE_SIZE).to_a
      return if recent.empty?

      send_buttons(channel, chat_id, recent)

      overflow = scope.count - PAGE_SIZE
      text = if overflow.positive?
        "Mais #{overflow} #{overflow == 1 ? 'gasto novo' : 'gastos novos'} no app"
      else
        "Gerencie no inbox do app"
      end
      send_footer(channel, chat_id, text)
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
      more  = total > shown ? shown : nil
      text  = more ? "Mostrando #{shown} de #{total} pendentes" : "Esses são todos os pendentes"
      send_footer(channel, chat_id, text, more_offset: more)
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

    # Rodapé único: opcionalmente "Ver mais 7" (paginação) e SEMPRE "Abrir no
    # app" embaixo — em vez de repetir o link em cada gasto.
    def send_footer(channel, chat_id, text, more_offset: nil)
      rows = []
      rows << [ { text: "Ver mais #{PAGE_SIZE}", callback_data: "inbox:more:#{more_offset}" } ] if more_offset
      rows << [ { text: "Abrir no app", url: inbox_url } ]
      channel.send_message(chat_id: chat_id, text: text, reply_markup: { inline_keyboard: rows })
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
          ]
        ]
      }
    end

    def inbox_url
      "https://#{ENV.fetch('APP_HOST')}/inbox"
    end
  end
end
