class Transaction < ApplicationRecord
  DIRECTIONS = %w[debit credit].freeze
  STATUSES   = %w[pending consolidated rejected split].freeze
  SOURCES    = %w[automatic_sync manual_import manual_entry installment_generated].freeze
  # Estado da análise IA (RF3/RF22): queued (aguardando), analyzed (a IA rodou),
  # failed (a IA não conseguiu — NÃO está aguardando). Ver migração ai_status.
  AI_STATUSES = %w[queued analyzed failed].freeze

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

  # RF11 — transferências internas. Uma transação participa de no máximo uma
  # (como débito de saída ou crédito de entrada).
  has_one :transfer_as_debit,  class_name: "InternalTransfer",
                               foreign_key: :debit_transaction_id, dependent: :destroy
  has_one :transfer_as_credit, class_name: "InternalTransfer",
                               foreign_key: :credit_transaction_id, dependent: :destroy

  validates :direction,            presence: true, inclusion: { in: DIRECTIONS }
  validates :amount_cents,         presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :occurred_at,          presence: true
  validates :original_description, presence: true
  validates :status,              presence: true, inclusion: { in: STATUSES }
  validates :source,              presence: true, inclusion: { in: SOURCES }
  validates :currency,            presence: true
  validates :ai_status,           presence: true, inclusion: { in: AI_STATUSES }

  attribute :status,    default: "pending"
  attribute :currency,  default: "BRL"
  attribute :ai_status, default: "queued"

  # external_transaction_id é coluna GERADA (source_metadata->>'id') — readonly.
  scope :inbox,        -> { where(status: "pending") }
  scope :consolidated, -> { where(status: "consolidated") }

  # Estado de análise IA (ver AI_STATUSES).
  scope :ai_queued,   -> { where(ai_status: "queued") }
  scope :ai_analyzed, -> { where(ai_status: "analyzed") }
  scope :ai_failed,   -> { where(ai_status: "failed") }

  # RF11 — exclui transações que participam de uma transferência interna (em
  # qualquer ponta). Usado nos relatórios pra não contar transferência como
  # gasto/receita.
  scope :not_internal_transfer, lambda {
    where.missing(:transfer_as_debit).where.missing(:transfer_as_credit)
  }

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

  # RF11 — participa de uma transferência interna (em qualquer ponta)?
  def internal_transfer?
    transfer_as_debit.present? || transfer_as_credit.present?
  end
end
