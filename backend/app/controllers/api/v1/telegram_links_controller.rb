class Api::V1::TelegramLinksController < ApplicationController
  before_action :require_authentication!

  LINK_CODE_TTL = 15.minutes

  # GET /api/v1/telegram_link — status do vínculo do workspace.
  def show
    render json: {
      linked:     current_workspace.telegram_chat_id.present?,
      chat_title: current_workspace.telegram_chat_title,
      linked_at:  current_workspace.telegram_linked_at&.iso8601
    }
  end

  # POST /api/v1/telegram_link — gera código de uso único + deep-link pro
  # grupo (startgroup: o usuário escolhe o grupo e o bot entra junto).
  def create
    code = SecureRandom.urlsafe_base64(24) # ≤64 chars, alfabeto aceito pelo deep-link
    current_workspace.update!(
      telegram_link_code:            code,
      telegram_link_code_expires_at: LINK_CODE_TTL.from_now
    )

    render json: {
      deep_link:  "https://t.me/#{ENV.fetch('TELEGRAM_BOT_USERNAME')}?startgroup=#{code}",
      expires_at: current_workspace.telegram_link_code_expires_at.iso8601
    }
  end

  # DELETE /api/v1/telegram_link — desvincula (novos eventos ficam só in-app).
  def destroy
    current_workspace.update!(
      telegram_chat_id: nil, telegram_chat_title: nil, telegram_linked_at: nil,
      telegram_link_code: nil, telegram_link_code_expires_at: nil
    )
    head :no_content
  end
end
