module AiSuggestion
  # Reanálise em massa sob demanda (RF3.5 — botão "Reanalisar com IA").
  # Processa todas as transações pending do workspace que ainda não têm
  # improved_title, têm confiança baixa, ou não têm tags.
  class ReanalyzeJob < ApplicationJob
    queue_as :default

    # Lote enviado à IA por chamada (P3): poucas chamadas ao Gemini em vez de
    # 1 por tx.
    BATCH_SIZE = 25

    def perform(workspace_id)
      workspace = Workspace.find_by(id: workspace_id)
      return unless workspace

      ids = eligible_transactions(workspace).pluck(:id)
      return if ids.empty?

      # Re-enfileira: volta pra "queued" e zera o snapshot ANTES de despachar.
      # Assim a barra de progresso reflete a reanálise e os "failed" voltam a
      # aguardar. As sugestões reais são regravadas pelo BatchSuggestJob.
      workspace.transactions.where(id: ids).update_all(ai_suggestion: nil, ai_status: "queued")

      ids.each_slice(BATCH_SIZE) do |batch_ids|
        AiSuggestion::BatchSuggestJob.perform_later(batch_ids)
      end
    end

    private

    def eligible_transactions(workspace)
      workspace.transactions
               .where(status: "pending")
               .where(
                 "ai_status = 'failed' OR improved_title IS NULL OR ai_confidence <= ? OR " \
                 "NOT EXISTS (SELECT 1 FROM transaction_tags tt WHERE tt.transaction_id = transactions.id)",
                 0.4
               )
    end
  end
end
