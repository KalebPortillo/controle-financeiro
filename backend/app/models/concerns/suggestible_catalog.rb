# Catálogo de sugestões da IA (RF3/RF22) — comportamento compartilhado por
# SuggestedTag e SuggestedCategory: ambos são itens "pending" escopados ao
# workspace que só viram registro real (Tag/Category) quando aceitos. Centraliza
# os status, validações, scopes e o upsert NÃO-DESTRUTIVO (nunca cria o registro
# real, não duplica um nome que já é real, não ressuscita accepted/dismissed).
module SuggestibleCatalog
  extend ActiveSupport::Concern

  STATUSES = %w[pending accepted dismissed].freeze

  included do
    belongs_to :workspace

    validates :name, presence: true,
                     uniqueness: { scope: :workspace_id, case_sensitive: false }
    validates :status, inclusion: { in: STATUSES }

    scope :pending,   -> { where(status: "pending") }
    scope :accepted,  -> { where(status: "accepted") }
    scope :dismissed, -> { where(status: "dismissed") }
  end

  class_methods do
    # Upsert não-destrutivo de uma sugestão pendente. `real_scope` é a coleção
    # de registros reais do workspace (tags/categories) e `suggestion_scope` é a
    # de sugestões. O bloco recebe a sugestão pra setar os campos específicos.
    # Retorna a sugestão, ou nil se ignorada (nome em branco / já é real).
    def upsert_pending(name:, real_scope:, suggestion_scope:)
      name = name.to_s.strip.truncate(50)
      return if name.blank?
      return if real_scope.exists?(name: name)

      suggestion = suggestion_scope.find_or_initialize_by(name: name)
      return suggestion if suggestion.persisted? && suggestion.status != "pending"

      suggestion.status = "pending"
      yield suggestion
      suggestion.save!
      suggestion
    end
  end
end
