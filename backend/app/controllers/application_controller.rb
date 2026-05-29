class ApplicationController < ActionController::API
  # Em API mode adicionamos cookies + session manualmente (ver application.rb).
  # `ActionController::Cookies` expõe `cookies` no controller; sessões já
  # ficam disponíveis via `session` quando o middleware está plugado.
  include ActionController::Cookies

  # Helpers de autenticação compartilhados — `current_user`, `signed_in?`,
  # `require_authentication!`. Detalhes em controllers/concerns/authentication.rb.
  include Authentication

  # Helpers de escopo por workspace — `current_workspace`, `current_membership`.
  # Disponível em todos os controllers; consultar apenas após sign-in.
  include WorkspaceScope

  # Renderização canônica de erros (formato em contratos-api.md v1.1).
  include ApiErrorResponses
end
