module AiSuggestion
  # Sugestão em LOTE (P2) — caminho corrente do inbox e da reanálise. Recebe ids
  # de transações, roda o BatchService (1 chamada ao provider pro lote) e
  # persiste o resultado por tx via Persist. Substitui o SuggestJob de 1 tx.
  class BatchSuggestJob < ApplicationJob
    queue_as :ai_suggestion

    # Gemini free tier: 15 RPM. 429 relança e o lote inteiro é re-tentado.
    retry_on AiProviders::ApiError, wait: :polynomially_longer, attempts: 5

    def perform(transaction_ids)
      txs = Transaction.where(id: transaction_ids, status: "pending").to_a
      return if txs.empty?

      results = AiSuggestion::BatchService.call(transactions: txs)
      txs.each { |tx| AiSuggestion::Persist.call(tx, results[tx.id]) if results[tx.id] }
      txs.first.workspace.clear_ai_error! # sucesso → some o banner de IA indisponível
    rescue AiProviders::ApiError => e
      # Feedback transparente: registra no workspace pra inbox mostrar o banner.
      Transaction.find_by(id: transaction_ids.first)&.workspace&.record_ai_error!(e)
      raise if e.retryable? # transitório → retry_on; quota → engole (sem retry inútil)
    end
  end
end
