module Categories
  # Sugere, on-demand, tags JÁ consolidadas que faltam numa categoria (RF6).
  # Candidatas = tags do workspace que ainda não estão na categoria. Grava as
  # sugestões pendentes em category_tag_suggestions (não ressuscita
  # accepted/dismissed). Disparado pelo botão "Sugerir tags" de cada categoria.
  class SuggestTagsJob < ApplicationJob
    queue_as :ai_suggestion

    retry_on AiProviders::ApiError, wait: :polynomially_longer, attempts: 3

    def perform(category_id)
      category  = Category.find_by(id: category_id)
      return unless category

      workspace  = category.workspace
      candidates = workspace.tags.where.not(id: category.tag_ids)
      return if candidates.empty?

      names = provider.suggest_tags_for_category(
        category_name:       category.name,
        member_tag_names:    category.tags.pluck(:name),
        candidate_tag_names: candidates.pluck(:name)
      )

      candidates.where(name: names).each do |tag|
        sug = category.category_tag_suggestions.find_or_initialize_by(tag_id: tag.id)
        next if sug.persisted? && sug.status != "pending" # não ressuscita

        sug.update!(status: "pending")
      end
      workspace.clear_ai_error!
    rescue AiProviders::ApiError => e
      workspace.record_ai_error!(e)
      raise if e.retryable?
    end

    private

    def provider
      AiProviders::GeminiProvider.new
    end
  end
end
