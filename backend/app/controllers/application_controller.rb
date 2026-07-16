class ApplicationController < ActionController::API
  # Em API mode adicionamos cookies + session manualmente (ver application.rb).
  # `ActionController::Cookies` expõe `cookies` no controller; sessões já
  # ficam disponíveis via `session` quando o middleware está plugado.
  include ActionController::Cookies

  # CSRF defense-in-depth: requests mutantes com Origin de outro host → 403.
  # Detalhes em controllers/concerns/origin_verification.rb.
  include OriginVerification

  # Helpers de autenticação compartilhados — `current_user`, `signed_in?`,
  # `require_authentication!`. Detalhes em controllers/concerns/authentication.rb.
  include Authentication

  # Helpers de escopo por workspace — `current_workspace`, `current_membership`.
  # Disponível em todos os controllers; consultar apenas após sign-in.
  include WorkspaceScope

  # Renderização canônica de erros (formato em contratos-api.md v1.1).
  include ApiErrorResponses

  private

  # RF16 — ações que ALTERAM o workspace (renomear, gerenciar membros) são só
  # pra editor; viewer é leitura. Não-membro nem chega aqui (lookups escopados
  # em current_user.workspaces devolvem 404 antes).
  def require_editor!(workspace)
    membership = workspace.memberships.find_by(user_id: current_user.id)
    return if membership&.role == "editor"

    render json: {
      error: { code: "forbidden", message: "Apenas editores podem fazer esta alteração." }
    }, status: :forbidden
  end
end
