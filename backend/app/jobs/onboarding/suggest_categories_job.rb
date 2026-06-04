module Onboarding
  # 2ª análise IA do onboarding (RF22): a partir das tags JÁ aceitas pelo usuário,
  # pede à IA categorias amplas que as agrupem e grava no catálogo
  # suggested_categories. Disparado quando o onboarding entra em "categorizing".
  #
  # Resiliente: se a IA falhar de vez (timeout/erro) após os retries, o bloco do
  # retry_on apenas desiste — o usuário cria categorias manualmente. Nunca trava
  # o fluxo (categorizing não depende deste job pra avançar).
  class SuggestCategoriesJob < ApplicationJob
    queue_as :ai_suggestion

    retry_on AiProviders::ApiError, wait: :polynomially_longer, attempts: 5 do |_job, _error|
      # Esgotou: segue sem sugestões. Nada a fazer — a UI permite criar manual.
      Rails.logger.warn("[SuggestCategoriesJob] desistiu após retries")
    end

    def perform(workspace_id)
      workspace = Workspace.find_by(id: workspace_id)
      return unless workspace

      tag_names = workspace.tags.pluck(:name)
      return if tag_names.empty?

      categories = provider.suggest_categories_from_tags(tag_names: tag_names)

      categories.each do |cat|
        SuggestedCategory.record(
          workspace: workspace,
          name:      cat[:name],
          tag_names: cat[:tag_names]
        )
      end
    end

    private

    def provider
      AiProviders::GeminiProvider.new
    end
  end
end
