module AiSuggestion
  # Sugestão em LOTE (P2) — caminho corrente do inbox e da reanálise. Recebe ids
  # de transações, roda o BatchService (1 chamada ao provider pro lote) e
  # persiste o resultado por tx via Persist. Substitui o SuggestJob de 1 tx.
  class BatchSuggestJob < ApplicationJob
    include AiResilient
    queue_as :ai_suggestion

    # Erro transitório (503/rate-limit) → re-tenta com backoff (banner só no
    # give-up); quota/daily → registra já, sem re-tentar. Ver AiResilient.
    retry_ai_errors(workspace_from: ->(job) { Transaction.find_by(id: job.arguments.first.first)&.workspace })

    def perform(transaction_ids)
      txs = Transaction.where(id: transaction_ids, status: "pending").to_a
      return if txs.empty?

      results = AiSuggestion::BatchService.call(transactions: txs)
      txs.each { |tx| AiSuggestion::Persist.call(tx, results[tx.id]) if results[tx.id] }
      txs.first.workspace.clear_ai_error! # sucesso → some o banner de IA indisponível
    rescue AiProviders::ApiError => e
      handle_ai_error(e, txs.first&.workspace)
    end
  end
end
