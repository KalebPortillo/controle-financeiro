module Onboarding
  # Análise IA do conjunto inicial de gastos (RF22).
  # - mode "discovery": primeira passagem, sem exclusões.
  # - mode "additive": passa tags/categorias existentes como exclusion list
  #   pra IA sugerir só o que falta (RF22.10).
  #
  # Quando termina, persiste suggested_tags e suggested_categories no
  # workspace.onboarding_state e transiciona pra "tagging".
  class AnalyzeJob < ApplicationJob
    include AiResilient
    queue_as :ai_suggestion

    # Transitório (503/rate-limit) → re-tenta com backoff (banner só no give-up);
    # quota/daily → registra já e mantém "analyzing" (o usuário segue manual). Não
    # auto-avança em silêncio: erro de IA fica TRANSPARENTE pro usuário. Ver AiResilient.
    retry_ai_errors(workspace_from: ->(job) { Workspace.find_by(id: job.arguments.first) })

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
    rescue AiProviders::ApiError => e
      handle_ai_error(e, workspace)
    end

    private

    def apply_result!(workspace, result, mode)
      # Sucesso de IA → limpa qualquer erro pendente (o card/banner some).
      workspace.clear_ai_error!

      # Alimenta o catálogo de sugestões (fonte única). Não-destrutivo, então um
      # AnalyzeJob tardio (ex.: usuário pulou a análise) nunca sobrescreve tags
      # já aceitas. As sugestões ficam disponíveis na etapa de tags / página / inbox.
      record_catalog_suggestions!(workspace, result[:tags])

      # Modo aditivo (RF22.10) NÃO transiciona o status — só repõe o catálogo.
      Onboarding::Service.advance(workspace, to: "tagging") if mode != "additive"
    end

    def record_catalog_suggestions!(workspace, tags)
      Array(tags).each do |tag|
        SuggestedTag.record(
          workspace: workspace,
          name:      tag[:name] || tag["name"],
          source:    "detected",
          rationale: tag[:rationale] || tag["rationale"],
          coverage:  tag[:coverage] || tag["coverage"]
        )
      end
    end

    def provider
      AiProviders::GeminiProvider.new
    end
  end
end
