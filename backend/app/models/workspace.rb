class Workspace < ApplicationRecord
  belongs_to :created_by_user, class_name: "User"

  # Ordem importa: dependent: :destroy roda na ordem de declaração. transactions
  # referenciam accounts (FK), então vão ANTES de accounts. bank_connections e
  # accounts referenciam workspace_memberships via owner_membership_id, então vão
  # ANTES das memberships, senão a FK estoura ao apagar o workspace.
  has_many :transactions, dependent: :destroy
  has_many :recurrences, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :suggested_tags, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :bank_connections, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :ai_learned_rules, dependent: :destroy
  has_many :memberships, class_name: "WorkspaceMembership", dependent: :destroy
  has_many :members, through: :memberships, source: :user

  validates :name, presence: true
end
