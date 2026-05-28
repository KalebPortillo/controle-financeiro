class Transaction < ApplicationRecord
  DIRECTIONS = %w[debit credit].freeze
  STATUSES   = %w[pending consolidated rejected split].freeze
  SOURCES    = %w[automatic_sync manual_import manual_entry installment_generated].freeze

  belongs_to :workspace
  belongs_to :account
  belongs_to :created_by_membership, class_name: "WorkspaceMembership", optional: true
  belongs_to :parent_transaction,    class_name: "Transaction", optional: true

  has_many :children, class_name: "Transaction", foreign_key: :parent_transaction_id,
                      dependent: :nullify

  validates :direction,            presence: true, inclusion: { in: DIRECTIONS }
  validates :amount_cents,         presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :occurred_at,          presence: true
  validates :original_description, presence: true
  validates :status,              presence: true, inclusion: { in: STATUSES }
  validates :source,              presence: true, inclusion: { in: SOURCES }
  validates :currency,            presence: true

  attribute :status,   default: "pending"
  attribute :currency, default: "BRL"

  # external_transaction_id é coluna GERADA (source_metadata->>'id') — readonly.
  scope :inbox,        -> { where(status: "pending") }
  scope :consolidated, -> { where(status: "consolidated") }

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end
end
