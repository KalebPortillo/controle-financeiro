class User < ApplicationRecord
  # Validações de identidade. Email é citext no schema, então a unicidade
  # também é case-insensitive — não precisamos do `case_sensitive: false`
  # do Rails (que seria um LOWER() em cima).
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  has_many :workspace_memberships, dependent: :destroy
  has_many :workspaces, through: :workspace_memberships

  validates :email,      presence: true, uniqueness: true, format: { with: EMAIL_FORMAT }
  validates :google_uid, presence: true, uniqueness: true
  validates :name,       presence: true

  # Upsert idempotente vindo do callback do Google OAuth.
  # `auth` é o OmniAuth::AuthHash que o omniauth-google-oauth2 entrega.
  def self.find_or_create_from_google(auth)
    user = find_or_initialize_by(google_uid: auth.uid)
    user.email      = auth.info.email
    user.name       = auth.info.name
    user.avatar_url = auth.info.image
    user.save!
    user
  end
end
