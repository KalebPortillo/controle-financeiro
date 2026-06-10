module Notifications
  # Resolve um /start <code> do webhook: acha o workspace dono do código
  # (válido e não expirado), grava o vínculo e queima o código. Confirmação
  # no grupo é best-effort (job) — falha de Telegram não desfaz o vínculo.
  module LinkTelegramChat
    module_function

    def call(code:, chat_id:, chat_title: nil)
      workspace = Workspace.where("telegram_link_code_expires_at > ?", Time.current)
                           .find_by(telegram_link_code: code)
      return nil unless workspace

      workspace.update!(
        telegram_chat_id:               chat_id,
        telegram_chat_title:            chat_title,
        telegram_linked_at:             Time.current,
        telegram_link_code:             nil,
        telegram_link_code_expires_at:  nil
      )

      TelegramLinkConfirmationJob.perform_later(workspace.id)
      workspace
    end
  end
end
