class Workspace < ApplicationRecord
  belongs_to :created_by_user, class_name: "User"

  has_many :memberships, class_name: "WorkspaceMembership", dependent: :destroy
  has_many :members, through: :memberships, source: :user

  validates :name, presence: true
end
