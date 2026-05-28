module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    # API mode não roda o middleware de sessão pro Cable, então lemos o user
    # direto do cookie de sessão encriptado (mesmo cookie HTTP-only do login).
    def find_verified_user
      user_id = cookies.encrypted[session_key]&.dig("user_id")
      User.find_by(id: user_id) || reject_unauthorized_connection
    end

    def session_key
      Rails.application.config.session_options[:key]
    end
  end
end
