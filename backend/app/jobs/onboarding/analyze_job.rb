module Onboarding
  # Análise IA do conjunto inicial de gastos (RF22).
  # - mode "discovery": primeira passagem, sem exclusões.
  # - mode "additive": passa tags/categorias existentes como exclusion list
  #   pra IA sugerir só o que falta (RF22.10).
  #
  # Quando termina, persiste suggested_tags e suggested_categories no
  # workspace.onboarding_state e transiciona pra "tagging".
  class AnalyzeJob < ApplicationJob
    queue_as :ai_suggestion

    retry_on AiProviders::ApiError, wait: :polynomially_longer, attempts: 5

    MAX_TRANSACTIONS = 200

    def perform(workspace_id, mode: "discovery")
      workspace = Workspace.find_by(id: workspace_id)
      return unless workspace

      txs = workspace.transactions
                     .where(status: "pending")
                     .order(occurred_at: :desc)
                     .limit(MAX_TRANSACTIONS)
                     .includes(:account)
                     .to_a
      return if txs.empty?

      context = txs.map do |tx|
        AiSuggestion::ContextExtractor.call(tx).merge(id: tx.id)
      end

      existing_tags       = mode == "additive" ? workspace.tags.pluck(:name) : []
      existing_categories = mode == "additive" ? workspace.categories.pluck(:name) : []

      result = provider.suggest_onboarding_discovery(
        transactions_context: context,
        existing_tags: existing_tags,
        existing_categories: existing_categories
      )

      apply_result!(workspace, result, mode)
    end

    private

    def apply_result!(workspace, result, mode)
      state = workspace.onboarding_state || {}

      # Em modo aditivo, NÃO transiciona o status — só guarda as sugestões
      # pendentes pro modal de revisão (RF22.10).
      next_status = mode == "additive" ? state["status"] : "tagging"

      workspace.update!(onboarding_state: state.merge(
        "status"               => next_status,
        "suggested_tags"       => result[:tags],
        "suggested_categories" => result[:categories]
      ))
    end

    def provider
      AiProviders::GeminiProvider.new
    end
  end
end
