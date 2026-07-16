class Api::V1::SessionsController < ApplicationController
  # `create` é o callback do OmniAuth — não pode exigir auth prévia.
  before_action :require_authentication!, only: [ :show, :destroy, :select_workspace ]
  # `failure` é invocada pelo on_failure do OmniAuth com o env ORIGINAL — se a
  # request phase POST foi rejeitada por Origin forjado, o env ainda carrega
  # esse Origin e o OriginVerification devolveria 403 JSON em vez do redirect
  # amigável. A action só redireciona (sem efeito colateral), então é seguro.
  skip_before_action :verify_request_origin, only: [ :failure ]

  # GET /api/v1/auth/:provider/callback
  # OmniAuth pôs o resultado em request.env["omniauth.auth"].
  def create
    auth  = request.env["omniauth.auth"]
    email = auth.dig("info", "email").to_s.downcase.strip

    unless email_allowed?(email)
      redirect_to "/?auth_error=unauthorized_email", allow_other_host: false
      return
    end

    user = Users::CreateWithPersonalWorkspace.call(auth)
    sign_in(user)
    # Inbox é a tela inicial — onde mora o trabalho diário.
    redirect_to "/inbox", allow_other_host: false
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
    # Workspace ativo resolvido pelo WorkspaceScope (mesma regra de todos os
    # controllers): o escolhido via select_workspace se ainda válido, senão o
    # primeiro do user.
    active_ws = current_workspace

    render json: {
      user:                serialize_user(current_user),
      workspaces:          workspaces.map { |w| serialize_workspace(w) },
      active_workspace_id: active_ws&.id,
      onboarding:          serialize_onboarding(active_ws)
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

    # E2E tests test post-onboarding flows by default. Skip onboarding so
    # RequireAuth doesn't redirect to /onboarding. Pass skip_onboarding=false
    # to test the onboarding flow itself.
    user.workspaces.first&.skip_onboarding! unless params[:skip_onboarding] == "false"

    head :no_content
  end

  private

  # ALLOWED_EMAILS — lista separada por vírgula de emails autorizados.
  # Fail-closed em production: sem a variável, NINGUÉM entra (staging e prod
  # têm dados reais; cadastro aberto por env esquecida seria a falha errada).
  # Em dev/test a lista vazia libera geral, pra não atrapalhar o fluxo local.
  def email_allowed?(email)
    raw = ENV["ALLOWED_EMAILS"].to_s.strip
    return !Rails.env.production? if raw.empty?

    raw.split(",").map { |e| e.strip.downcase }.include?(email)
  end

  # Resumo do estado de onboarding pro frontend decidir se redireciona
  # ao /onboarding no boot. Membros convidados (não donos) recebem nil — pra eles
  # o fluxo não existe e o app abre normal.
  def serialize_onboarding(workspace)
    return nil if workspace.nil? || workspace.created_by_user_id != current_user.id

    state = workspace.onboarding_state || {}
    { status: state["status"], current_step: onboarding_step_for(state["status"]) }
  end

  def onboarding_step_for(status)
    case status
    when "not_started", nil then 0
    when "connecting"       then 1
    when "analyzing"        then 2
    when "tagging"          then 3
    end
  end

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
end
