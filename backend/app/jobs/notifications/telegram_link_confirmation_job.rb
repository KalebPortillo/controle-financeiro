module Notifications
  # Mensagem de boas-vindas no grupo recém-vinculado. Best-effort: se falhar,
  # o vínculo continua de pé (o card de config já mostra "vinculado").
  class TelegramLinkConfirmationJob < ApplicationJob
    queue_as :default

    discard_on NotificationChannels::Error
    discard_on ActiveRecord::RecordNotFound

    def perform(workspace_id, channel: NotificationChannels::Telegram.new)
      workspace = Workspace.find(workspace_id)
      return if workspace.telegram_chat_id.blank?

      channel.send_message(
        chat_id: workspace.telegram_chat_id,
        text:    "Grupo vinculado ao workspace #{workspace.name}. " \
                 "Vocês receberão os avisos do controle financeiro por aqui."
      )
    end
  end
end
