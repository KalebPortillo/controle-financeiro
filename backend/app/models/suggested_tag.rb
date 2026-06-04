# Tag sugerida pela IA (RF3/RF22), separada das Tags reais (aceitas). Nasce no
# onboarding (Onboarding::AnalyzeJob) ou na inbox (AiSuggestion::SuggestJob) com
# status "pending" e só vira uma Tag de verdade quando aceita pelo usuário.
class SuggestedTag < ApplicationRecord
  include SuggestibleCatalog

  SOURCES = %w[detected manual inbox].freeze

  validates :source, inclusion: { in: SOURCES }
  validates :coverage, numericality: { greater_than_or_equal_to: 0 }

  # Registra um nome como sugestão pendente (não-destrutivo — ver SuggestibleCatalog).
  # source: origem (detected/manual/inbox); coverage acumula quantas transações encaixam.
  def self.record(workspace:, name:, source:, rationale: nil, coverage: nil)
    upsert_pending(name: name, real_scope: workspace.tags, suggestion_scope: workspace.suggested_tags) do |s|
      s.source ||= source
      s.rationale = rationale if rationale.present?
      s.coverage = coverage || s.coverage.to_i + 1
    end
  end
end
