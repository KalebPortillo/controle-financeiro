# Resiliência compartilhada dos jobs de IA (RF22) ao free tier do Gemini.
#
# Erros transitórios (503/overload, rate-limit por minuto) são re-tentados com
# backoff até passarem — SEM mostrar o banner de erro durante as tentativas (a
# barra de progresso já indica "analisando"). O banner só aparece quando:
#   - o erro é PERMANENTE (quota/daily): registra na hora, sem re-tentar; ou
#   - os retries se ESGOTAM (serviço realmente fora): registra no give-up.
#
# Quem inclui passa `workspace_from:` (lambda que extrai o Workspace do job) e,
# no rescue do perform, chama `handle_ai_error(e, workspace)`.
module AiResilient
  extend ActiveSupport::Concern

  RETRY_ATTEMPTS = 5
  # Backoff curto e limitado: 503 do free tier costuma liberar em segundos.
  # 8s, 16s, 24s, 30s (cap). Re-enfileira (não bloqueia a fila de 1 thread).
  RETRY_WAIT = ->(executions) { [ executions * 8, 30 ].min }

  class_methods do
    # workspace_from: lambda(job) -> Workspace|nil (pra registrar o erro).
    # on_give_up: lambda(job, error) opcional — trabalho extra no give-up (ex.:
    # marcar as transações do lote como "failed" pra saírem de "aguardando").
    def retry_ai_errors(workspace_from:, on_give_up: nil)
      retry_on AiProviders::ApiError, wait: RETRY_WAIT, attempts: RETRY_ATTEMPTS do |job, error|
        # Esgotou os retries de um erro transitório → agora sim é um problema
        # real: registra pra UI mostrar o banner.
        workspace_from.call(job)&.record_ai_error!(error)
        on_give_up&.call(job, error)
      end
    end
  end

  private

  # Chamado no rescue AiProviders::ApiError do perform.
  # - permanente (quota/daily): registra já e encerra (sem re-tentar);
  # - transitório: re-lança pro retry_on (banner só no give-up).
  def handle_ai_error(error, workspace)
    raise error if error.retryable?

    workspace&.record_ai_error!(error)
  end
end
