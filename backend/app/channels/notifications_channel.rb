# Empurra notificações novas (RF17) pro sininho em tempo real. Escopado por
# workspace: só membros assinam. O broadcast (disparado por Notifications::Create)
# carrega `{ event: "notification_created", notification: {...} }` com o mesmo
# schema do REST.
class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    workspace = current_user.workspaces.find_by(id: params[:workspace_id])
    return reject unless workspace

    stream_for workspace
  end
end
