# Uma execução de sync de uma conexão (RF21.7 — histórico das últimas N). O
# Sync grava uma linha por run, em sucesso ou erro.
class BankConnectionSync < ApplicationRecord
  STATUSES = %w[success error].freeze

  belongs_to :bank_connection

  validates :status,     presence: true, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc) }
end
