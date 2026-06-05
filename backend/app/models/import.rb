# RF20 — registro de um upload de arquivo (CSV/OFX) cujas linhas viram transações
# na inbox. O arquivo fica no Active Storage; o processamento é assíncrono
# (Imports::ProcessJob) e os contadores/erros são gravados aqui pro feedback.
class Import < ApplicationRecord
  FORMATS  = %w[csv ofx].freeze
  STATUSES = %w[pending processing completed failed].freeze
  MAX_BYTES = 10 * 1024 * 1024 # 10 MB (RF20 / decisão de contrato)

  belongs_to :workspace
  belongs_to :uploaded_by_membership, class_name: "WorkspaceMembership"
  belongs_to :account, optional: true

  has_one_attached :file

  validates :filename, presence: true
  validates :format, presence: true, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def processing!
    update!(status: "processing", started_at: Time.current)
  end

  # errors: array de { "row" => N|nil, "message" => "..." }.
  def complete!(created:, duplicate:, errors: [])
    update!(
      status:          "completed",
      created_count:   created,
      duplicate_count: duplicate,
      error_count:     errors.size,
      error_log:       errors,
      completed_at:    Time.current
    )
  end

  def fail!(message)
    update!(status: "failed", error_log: [ { "row" => nil, "message" => message } ],
            error_count: 1, completed_at: Time.current)
  end
end
