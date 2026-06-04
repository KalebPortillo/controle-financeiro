# Endpoints comuns dos catálogos de sugestões da IA (suggested_tags /
# suggested_categories): index (pendentes, serializadas) e destroy (recusar →
# dismissed). O `accept` é específico de cada controller (tag vira Tag e pode
# aplicar a uma transação; categoria vira Category e associa tags), assim como
# o `serialize`. Quem inclui define:
#   - suggestion_scope  → coleção de sugestões do workspace (ex.: suggested_tags)
#   - serialize(s)       → hash JSON de uma sugestão
#   - index_root         → chave raiz do JSON da listagem (ex.: :suggested_tags)
#   - index_order        → (opcional) ordenação do index
module SuggestionsEndpoint
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication!
    before_action :set_suggestion, only: [ :accept, :destroy ]
  end

  # GET — sugestões pendentes do workspace.
  def index
    suggestions = suggestion_scope.pending.order(index_order)
    render json: { index_root => suggestions.map { |s| serialize(s) } }
  end

  # DELETE — recusa a sugestão (status dismissed).
  def destroy
    @suggestion.update!(status: "dismissed")
    head :no_content
  end

  private

  def set_suggestion
    @suggestion = suggestion_scope.find(params[:id])
  end
end
