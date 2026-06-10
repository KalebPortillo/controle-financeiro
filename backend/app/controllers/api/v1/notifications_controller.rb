class Api::V1::NotificationsController < ApplicationController
  before_action :require_authentication!

  # GET /api/v1/notifications?unread=true — broadcast + dirigidas a mim.
  def index
    scope = visible_notifications.recent
    scope = scope.unread if params[:unread] == "true"

    render json: {
      notifications: scope.limit(50).map { |n| Notifications::Serializer.call(n) },
      unread_count:  visible_notifications.unread.count
    }
  end

  # POST /api/v1/notifications/:id/mark_read
  def mark_read
    notification = visible_notifications.find(params[:id])
    notification.mark_read!
    render json: { notification: Notifications::Serializer.call(notification) }
  end

  # POST /api/v1/notifications/mark_all_read
  def mark_all_read
    visible_notifications.unread.update_all(read_at: Time.current)
    head :ok
  end

  private

  def visible_notifications
    current_workspace.notifications.visible_to(current_membership)
  end
end
