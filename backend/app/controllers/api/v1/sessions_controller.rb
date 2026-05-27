class Api::V1::SessionsController < ApplicationController
  # `create` é o callback do OmniAuth — não pode exigir auth prévia.
  before_action :require_authentication!, only: [ :show, :destroy, :select_workspace ]

  # GET /api/v1/auth/:provider/callback
  # OmniAuth pôs o resultado em request.env["omniauth.auth"].
  def create
    auth = request.env["omniauth.auth"]
    user = Users::CreateWithPersonalWorkspace.call(auth)
    sign_in(user)

    # Frontend lida com o estado; o callback só fixa a sessão e devolve
    # o navegador pra raiz.
    redirect_to "/", allow_other_host: false
  end

  # GET /api/v1/auth/failure
  # OmniAuth redireciona pra cá quando o handshake falha (state inválido,
  # credentials revogadas, user cancelou).
  def failure
    redirect_to "/?auth_error=#{params[:message] || 'unknown'}", allow_other_host: false
  end

  # GET /api/v1/sessions/current
  def show
    workspaces = current_user.workspaces.order(:created_at)
    render json: {
      user:                serialize_user(current_user),
      workspaces:          workspaces.map { |w| serialize_workspace(w) },
      active_workspace_id: active_workspace_id(workspaces)
    }
  end

  # DELETE /api/v1/sessions/current
  def destroy
    sign_out
    head :no_content
  end

  # POST /api/v1/sessions/current/select_workspace { workspace_id }
  def select_workspace
    workspace = current_user.workspaces.find(params[:workspace_id])
    session[:active_workspace_id] = workspace.id
    render json: { active_workspace_id: workspace.id }
  end

  # POST /api/v1/auth/test_sign_in { email, name? }
  # Atalho para Playwright (E2E). Cria/loga user via o MESMO service que o
  # callback OAuth real (Users::CreateWithPersonalWorkspace) — diferença é
  # só que pulamos o handshake Google. Rota disponível apenas em
  # non-production (gate em routes.rb).
  def test_sign_in
    auth = OmniAuth::AuthHash.new(
      provider: "test",
      uid:      "test-#{params[:email]}",
      info: {
        email: params[:email],
        name:  params[:name].presence || "Test User",
        image: nil
      }
    )
    user = Users::CreateWithPersonalWorkspace.call(auth)
    sign_in(user)
    head :no_content
  end

  private

  def serialize_user(user)
    {
      id:         user.id,
      email:      user.email,
      name:       user.name,
      avatar_url: user.avatar_url
    }
  end

  def serialize_workspace(workspace)
    { id: workspace.id, name: workspace.name }
  end

  # Workspace ativo: o que foi escolhido explicitamente via select_workspace
  # (se ainda for válido), senão o primeiro do user. Sempre validado contra
  # a lista atual de memberships pra evitar IDs órfãos na sessão.
  def active_workspace_id(workspaces)
    selected = session[:active_workspace_id]
    return selected if selected && workspaces.any? { |w| w.id == selected }

    workspaces.first&.id
  end
end
