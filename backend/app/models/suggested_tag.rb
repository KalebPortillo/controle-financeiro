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

  # Registra um nome como sugestão pendente do workspace, de forma não-destrutiva:
  # nunca cria Tag real, não duplica um nome que já é tag real, e não ressuscita
  # uma sugestão já aceita ou recusada. Compartilhado por AnalyzeJob (descoberta
  # do onboarding) e SuggestJob (inbox). Retorna a SuggestedTag ou nil se ignorada.
  def self.record(workspace:, name:, source:, rationale: nil, coverage: nil)
    name = name.to_s.strip.truncate(50)
    return if name.blank?
    return if workspace.tags.exists?(name: name)

    suggestion = workspace.suggested_tags.find_or_initialize_by(name: name)
    return suggestion if suggestion.persisted? && suggestion.status != "pending"

    suggestion.source ||= source
    suggestion.status = "pending"
    suggestion.rationale = rationale if rationale.present?
    suggestion.coverage = coverage || suggestion.coverage.to_i + 1
    suggestion.save!
    suggestion
  end
end
