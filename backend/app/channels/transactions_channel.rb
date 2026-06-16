# Empurra mudança de status das transações (RF2.3) pra inbox em tempo real.
# Escopado por workspace: só membros assinam. Quando alguém decide (consolida/
# rejeita) num canal (web/Telegram), o item some da inbox do outro membro sem
# refresh. O broadcast (model em after_update_commit) carrega { event, id, status }.
class TransactionsChannel < ApplicationCable::Channel
  def subscribed
    workspace = current_user.workspaces.find_by(id: params[:workspace_id])
    return reject unless workspace

    stream_for workspace
  end
end
