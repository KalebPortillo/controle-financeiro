module Notifications
  # Envia, pro grupo vinculado, uma mensagem com botões inline por transação
  # nova pendente (RF17) — Consolidar / Rejeitar / Abrir no app. Telegram-only:
  # não cria Notification in-app (o resumo inbox_new já cobre o sininho).
  # Disparado pelo Sync quando o lote é pequeno (≤ TELEGRAM_INBOX_BUTTONS_MAX).
  module TelegramInboxButtons
    module_function

    def call(workspace:, transaction_ids:, channel: NotificationChannels::Telegram.new)
      chat_id = workspace.telegram_chat_id
      return if chat_id.blank?

      workspace.transactions
               .where(id: transaction_ids, status: "pending")
               .includes(:account).order(:created_at).each do |tx|
        channel.send_message(chat_id: chat_id, text: text_for(tx), reply_markup: keyboard_for(tx))
      end
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
          [ { text: "Abrir no app", url: "https://#{ENV.fetch('APP_HOST')}/inbox" } ]
        ]
      }
    end
  end
end
