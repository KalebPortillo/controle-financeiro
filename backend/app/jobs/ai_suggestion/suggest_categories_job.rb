module AiSuggestion
  # Sugestão de categorias on-demand (tela de Categorias). A partir das tags
  # consolidadas do workspace, pede à IA categorias amplas que as agrupem,
  # EXCLUINDO as categorias que já existem (reais ou já sugeridas pendentes) pra
  # não duplicar, e grava até CATEGORIES_LIMIT no catálogo suggested_categories.
  #
  # Disparado pelo botão "Sugerir categorias com IA" (substitui o antigo
  # Onboarding::SuggestCategoriesJob, que rodava na 2ª análise do onboarding).
  class SuggestCategoriesJob < ApplicationJob
    queue_as :ai_suggestion

    retry_on AiProviders::ApiError, wait: :polynomially_longer, attempts: 3

    def perform(workspace_id)
      workspace = Workspace.find_by(id: workspace_id)
      return unless workspace

      tag_names = workspace.tags.pluck(:name)
      return if tag_names.empty?

      existing = workspace.categories.pluck(:name) +
                 workspace.suggested_categories.pending.pluck(:name)

      categories = provider.suggest_categories_from_tags(
        tag_names: tag_names, existing_categories: existing.uniq
      )

      categories.each do |cat|
        SuggestedCategory.record(workspace: workspace, name: cat[:name], tag_names: cat[:tag_names])
      end
      workspace.clear_ai_error! # sucesso → some o erro de IA
    rescue AiProviders::ApiError => e
      workspace.record_ai_error!(e)
      raise if e.retryable? # transitório → retry_on; quota → engole
    end

    private

    def provider
      AiProviders::GeminiProvider.new
    end
  end
end
