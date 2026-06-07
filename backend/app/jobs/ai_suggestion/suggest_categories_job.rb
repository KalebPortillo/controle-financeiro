module AiSuggestion
  # Sugestão de categorias on-demand (tela de Categorias). A partir das tags
  # consolidadas do workspace, pede à IA categorias amplas que as agrupem,
  # EXCLUINDO as categorias que já existem (reais ou já sugeridas pendentes) pra
  # não duplicar, e grava até CATEGORIES_LIMIT no catálogo suggested_categories.
  #
  # Disparado pelo botão "Sugerir categorias com IA" (substitui o antigo
  # Onboarding::SuggestCategoriesJob, que rodava na 2ª análise do onboarding).
  class SuggestCategoriesJob < ApplicationJob
    include AiResilient
    queue_as :ai_suggestion

    retry_ai_errors(workspace_from: ->(job) { Workspace.find_by(id: job.arguments.first) })

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
      handle_ai_error(e, workspace)
    end

    private

    def provider
      AiProviders::GeminiProvider.new
    end
  end
end
