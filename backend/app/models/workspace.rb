class Workspace < ApplicationRecord
  belongs_to :created_by_user, class_name: "User"

  has_many :memberships, class_name: "WorkspaceMembership", dependent: :destroy
  has_many :members, through: :memberships, source: :user
  has_many :bank_connections, dependent: :destroy
  has_many :accounts, dependent: :destroy

  validates :name, presence: true
end
