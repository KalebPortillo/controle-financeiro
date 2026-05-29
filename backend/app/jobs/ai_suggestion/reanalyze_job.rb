module AiSuggestion
  # Reanálise em massa sob demanda (RF3.5 — botão "Reanalisar com IA").
  # Processa todas as transações pending do workspace que ainda não têm
  # improved_title, têm confiança baixa, ou não têm tags.
  class ReanalyzeJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 50

    def perform(workspace_id)
      workspace = Workspace.find_by(id: workspace_id)
      return unless workspace

      eligible_transactions(workspace).find_each(batch_size: BATCH_SIZE) do |tx|
        AiSuggestion::SuggestJob.perform_later(tx.id)
      end
    end

    private

    def eligible_transactions(workspace)
      workspace.transactions
               .where(status: "pending")
               .where(
                 "improved_title IS NULL OR ai_confidence <= ? OR " \
                 "NOT EXISTS (SELECT 1 FROM transaction_tags tt WHERE tt.transaction_id = transactions.id)",
                 0.4
               )
    end
  end
end
