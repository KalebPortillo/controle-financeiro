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

    # Re-tenta erros de rede/API com backoff. Se esgotar as tentativas, o bloco
    # garante que o onboarding NÃO fique preso em "analyzing": avança pra
    # "tagging" com sugestões vazias (modo discovery) — o usuário segue manual.
    retry_on AiProviders::ApiError, wait: :polynomially_longer, attempts: 5 do |job, _error|
      workspace_id, options = job.arguments
      mode = (options || {})[:mode] || "discovery"
      next if mode == "additive"

      workspace = Workspace.find_by(id: workspace_id)
      next unless workspace && workspace.onboarding_state&.dig("status") == "analyzing"

      Onboarding::Service.advance(workspace, to: "tagging")
    end

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
