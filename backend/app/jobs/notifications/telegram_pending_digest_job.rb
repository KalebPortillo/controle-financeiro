module Notifications
  # Async (best-effort, molde do TelegramInboxButtonsJob) do digest de pendentes:
  # comando /pendentes e botão "ver mais" (paginação por `offset`). Manter fora do
  # request do webhook — pode enviar várias mensagens ao Telegram.
  class TelegramPendingDigestJob < ApplicationJob
    queue_as :default

    retry_on NotificationChannels::RateLimitError, wait: 30.seconds, attempts: 3
    discard_on NotificationChannels::ApiError
    discard_on ActiveRecord::RecordNotFound

    def perform(workspace_id, offset = 0)
      workspace = Workspace.find(workspace_id)
      TelegramInboxButtons.push_pending(workspace: workspace, offset: offset)
    end
  end
end
