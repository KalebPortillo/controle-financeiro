class BankConnection < ApplicationRecord
  PROVIDERS = %w[pluggy manual].freeze
  STATUSES  = %w[connected syncing expired error disconnected].freeze

  belongs_to :workspace
  belongs_to :owner_membership, class_name: "WorkspaceMembership"

  has_many :accounts, dependent: :nullify

  validates :provider,               presence: true, inclusion: { in: PROVIDERS }
  validates :status,                 presence: true, inclusion: { in: STATUSES }
  validates :external_connection_id, presence: true, uniqueness: { scope: :provider }
  validates :sync_history_since,     presence: true

  attribute :provider, default: "pluggy"
  attribute :status,   default: "connected"

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end
end
