module Authentication
  extend ActiveSupport::Concern

  # Lê o user da sessão e expõe `current_user` / `signed_in?` em todos os
  # controllers. Quem precisa de auth obrigatória chama `require_authentication!`
  # num before_action.
  def current_user
    return @current_user if defined?(@current_user)

    @current_user = session[:user_id].present? ? User.find_by(id: session[:user_id]) : nil
  end

  def signed_in?
    current_user.present?
  end

  def require_authentication!
    return if signed_in?

    render_unauthenticated
  end

  def sign_in(user)
    # Rotaciona o id da sessão pra prevenir fixation — o cookie velho deixa
    # de identificar quem quer que tenha feito a tentativa anterior.
    reset_session
    session[:user_id] = user.id
    @current_user = user
  end

  def sign_out
    reset_session
    @current_user = nil
  end

  def render_unauthenticated
    render json: { error: { code: "unauthenticated", message: "Sign in required." } },
           status: :unauthorized
  end
end
