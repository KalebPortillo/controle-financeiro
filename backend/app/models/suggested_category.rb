# Categoria sugerida pela IA (RF22), separada das Categories reais (aceitas).
# Nasce na 2ª análise do onboarding (Onboarding::SuggestCategoriesJob), a partir
# das tags efetivamente aceitas, com status "pending" — só vira uma Category de
# verdade quando aceita pelo usuário. `tag_names` guarda as tags que devem
# compor a categoria (resolvidas a ids no aceite).
class SuggestedCategory < ApplicationRecord
  include SuggestibleCatalog

  # Registra um nome como sugestão pendente (não-destrutivo — ver SuggestibleCatalog).
  def self.record(workspace:, name:, tag_names: [])
    upsert_pending(name: name, real_scope: workspace.categories, suggestion_scope: workspace.suggested_categories) do |s|
      s.tag_names = Array(tag_names).map { |n| n.to_s.strip }.reject(&:blank?).uniq
    end
  end
end
