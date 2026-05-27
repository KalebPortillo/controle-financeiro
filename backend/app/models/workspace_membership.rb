class WorkspaceMembership < ApplicationRecord
  ROLES = %w[editor viewer].freeze

  belongs_to :user
  belongs_to :workspace

  validates :role,      presence: true, inclusion: { in: ROLES }
  validates :joined_at, presence: true
  validates :user_id,   uniqueness: { scope: :workspace_id }

  attribute :role, default: "editor"
end
