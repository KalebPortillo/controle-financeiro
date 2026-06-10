class WorkspaceMembership < ApplicationRecord
  ROLES = %w[editor viewer].freeze

  belongs_to :user
  belongs_to :workspace

  has_many :owned_bank_connections, class_name: "BankConnection",
                                    foreign_key: :owner_membership_id,
                                    dependent: :nullify, inverse_of: :owner_membership
  has_many :owned_accounts, class_name: "Account",
                            foreign_key: :owner_membership_id,
                            dependent: :nullify, inverse_of: :owner_membership

  validates :role,      presence: true, inclusion: { in: ROLES }
  validates :joined_at, presence: true
  validates :user_id,   uniqueness: { scope: :workspace_id }

  attribute :role, default: "editor"
end
