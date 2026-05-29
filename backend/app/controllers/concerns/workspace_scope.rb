module WorkspaceScope
  extend ActiveSupport::Concern

  private

  # Workspace ativo: o escolhido via select_workspace (se ainda for válido)
  # ou o primeiro do user. Sempre validado contra a lista atual de memberships
  # pra evitar IDs órfãos na sessão.
  def current_workspace
    return @current_workspace if defined?(@current_workspace)

    workspaces = current_user.workspaces
    selected   = session[:active_workspace_id]
    @current_workspace =
      (selected && workspaces.find_by(id: selected)) ||
      workspaces.order(:created_at).first
  end

  # Membership do user atual no workspace ativo — usado em ações que
  # registram autoria (TransactionEdit, criação de transação manual etc).
  def current_membership
    return @current_membership if defined?(@current_membership)

    @current_membership = current_user.workspace_memberships.find_by(workspace: current_workspace)
  end
end
