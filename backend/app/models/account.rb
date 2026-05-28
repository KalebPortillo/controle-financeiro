class Account < ApplicationRecord
  KINDS        = %w[checking credit_card].freeze
  INSTITUTIONS = %w[nubank inter itau santander bb manual].freeze

  belongs_to :workspace
  belongs_to :owner_membership, class_name: "WorkspaceMembership"
  belongs_to :bank_connection, optional: true

  validates :name,        presence: true
  validates :kind,        presence: true, inclusion: { in: KINDS }
  validates :institution, presence: true, inclusion: { in: INSTITUTIONS }
  validates :currency,    presence: true
  validates :external_id, uniqueness: { scope: :bank_connection_id }, allow_nil: true

  attribute :currency, default: "BRL"

  KINDS.each do |k|
    define_method("#{k}?") { kind == k }
  end
end
