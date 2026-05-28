# Empurra o status das conexões bancárias pro painel de sync (RF21) em tempo
# real. Escopado por workspace: só membros assinam. O broadcast (disparado
# pelo model em after_update_commit) carrega `{ event: "connection_updated",
# bank_connection: {...} }` com o mesmo schema do REST.
class BankConnectionsChannel < ApplicationCable::Channel
  def subscribed
    workspace = current_user.workspaces.find_by(id: params[:workspace_id])
    return reject unless workspace

    stream_for workspace
  end
end
