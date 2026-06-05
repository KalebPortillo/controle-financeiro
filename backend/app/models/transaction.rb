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

  has_many :transaction_tags, dependent: :destroy
  has_many :tags, through: :transaction_tags

  has_many :edits, class_name: "TransactionEdit", dependent: :delete_all

  # RF10 — estornos. Como gasto (debit): pode receber vários estornos. Como
  # estorno (credit): vincula a no máximo um gasto.
  has_many :refunds_received, class_name: "TransactionRefund",
                              foreign_key: :refunded_transaction_id, dependent: :destroy
  has_one  :refund_of, class_name: "TransactionRefund",
                       foreign_key: :refund_transaction_id, dependent: :destroy

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

  # RF10 — soma dos estornos recebidos por este gasto (em centavos).
  def refunded_amount_cents
    refunds_received.sum { |r| r.refund_transaction.amount_cents }
  end

  def refunded?
    refunds_received.any?
  end

  # Valor consolidado efetivo do gasto: original menos estornos, nunca negativo
  # (RF10.3). Para créditos/sem estorno, devolve o próprio amount_cents.
  def effective_amount_cents
    [ amount_cents - refunded_amount_cents, 0 ].max
  end
end
