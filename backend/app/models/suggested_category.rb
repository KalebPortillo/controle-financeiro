# Categoria sugerida pela IA (RF22), separada das Categories reais (aceitas).
# Nasce na 2ª análise do onboarding (Onboarding::SuggestCategoriesJob), a partir
# das tags efetivamente aceitas, com status "pending" — só vira uma Category de
# verdade quando aceita pelo usuário. `tag_names` guarda as tags que devem
# compor a categoria (resolvidas a ids no aceite).
class SuggestedCategory < ApplicationRecord
  STATUSES = %w[pending accepted dismissed].freeze

  belongs_to :workspace

  validates :name, presence: true,
                   uniqueness: { scope: :workspace_id, case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }

  scope :pending,   -> { where(status: "pending") }
  scope :accepted,  -> { where(status: "accepted") }
  scope :dismissed, -> { where(status: "dismissed") }

  # Upsert não-destrutivo (espelha SuggestedTag.record): nunca cria Category real,
  # não duplica nome que já é categoria real, não ressuscita accepted/dismissed.
  def self.record(workspace:, name:, tag_names: [])
    name = name.to_s.strip.truncate(50)
    return if name.blank?
    return if workspace.categories.exists?(name: name)

    suggestion = workspace.suggested_categories.find_or_initialize_by(name: name)
    return suggestion if suggestion.persisted? && suggestion.status != "pending"

    suggestion.status = "pending"
    suggestion.tag_names = Array(tag_names).map { |n| n.to_s.strip }.reject(&:blank?).uniq
    suggestion.save!
    suggestion
  end
end
