# Tag sugerida pela IA (RF3/RF22), separada das Tags reais (aceitas). Nasce no
# onboarding (Onboarding::AnalyzeJob) ou na inbox (AiSuggestion::SuggestJob) com
# status "pending" e só vira uma Tag de verdade quando aceita pelo usuário.
class SuggestedTag < ApplicationRecord
  SOURCES  = %w[detected manual inbox].freeze
  STATUSES = %w[pending accepted dismissed].freeze

  belongs_to :workspace

  validates :name, presence: true,
                   uniqueness: { scope: :workspace_id, case_sensitive: false }
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :coverage, numericality: { greater_than_or_equal_to: 0 }

  scope :pending,   -> { where(status: "pending") }
  scope :accepted,  -> { where(status: "accepted") }
  scope :dismissed, -> { where(status: "dismissed") }
end
