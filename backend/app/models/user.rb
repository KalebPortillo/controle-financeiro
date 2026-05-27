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
end
