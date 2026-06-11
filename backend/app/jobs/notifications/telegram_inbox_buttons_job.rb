module Notifications
  # Wrapper async do TelegramInboxButtons (best-effort, molde do
  # TelegramDeliveryJob): retry só em rate limit, descarta erro permanente.
  class TelegramInboxButtonsJob < ApplicationJob
    queue_as :default

    retry_on NotificationChannels::RateLimitError, wait: 30.seconds, attempts: 3
    discard_on NotificationChannels::ApiError
    discard_on ActiveRecord::RecordNotFound

    def perform(workspace_id, transaction_ids)
      workspace = Workspace.find(workspace_id)
      TelegramInboxButtons.call(workspace: workspace, transaction_ids: transaction_ids)
    end
  end
end
