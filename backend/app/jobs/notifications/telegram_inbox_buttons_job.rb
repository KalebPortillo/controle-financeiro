module Notifications
  # Wrapper async do TelegramInboxButtons (best-effort, molde do
  # TelegramDeliveryJob): retry só em rate limit, descarta erro permanente.
  #
  # Antes de mandar, ESPERA a IA sugerir tags (a transação sai de ai_status
  # "queued") pra a mensagem já ir com "Sugestão: …" — a análise roda em paralelo
  # (BatchSuggestJob) e costuma terminar em segundos. A cada rodada reagenda a si
  # mesmo com um pequeno delay. Failsafe: passado MAX_WAIT_SECONDS, manda mesmo sem
  # sugestão — a IA falhando/atrasando não pode travar a notificação de gasto novo.
  class TelegramInboxButtonsJob < ApplicationJob
    queue_as :default

    retry_on NotificationChannels::RateLimitError, wait: 30.seconds, attempts: 3
    # Telegram fora do ar por alguns segundos não pode custar o lote inteiro: o
    # envio é retomável (TelegramInboxButtons carimba cada gasto entregue), então
    # re-tentar manda só o que faltou. Sem isso o job ia direto pra
    # FailedExecution e os gastos restantes nunca apareciam no grupo.
    retry_on NotificationChannels::TransientError, wait: :polynomially_longer, attempts: 5
    discard_on NotificationChannels::ApiError
    discard_on ActiveRecord::RecordNotFound

    POLL_WAIT_SECONDS = 15
    MAX_WAIT_SECONDS   = 180

    def perform(workspace_id, transaction_ids, waited_seconds = 0)
      workspace = Workspace.find(workspace_id)

      if waited_seconds < MAX_WAIT_SECONDS && awaiting_suggestions?(workspace, transaction_ids)
        self.class.set(wait: POLL_WAIT_SECONDS.seconds)
            .perform_later(workspace_id, transaction_ids, waited_seconds + POLL_WAIT_SECONDS)
        return
      end

      TelegramInboxButtons.call(workspace: workspace, transaction_ids: transaction_ids)
    end

    private

    # Ainda há transação do lote aguardando a IA (ai_status "queued")? Quando todas
    # já foram analisadas OU falharam ("analyzed"/"failed"), ou saíram de pending,
    # segue — inclusive no caso de falha da IA (aí manda sem sugestão).
    def awaiting_suggestions?(workspace, transaction_ids)
      workspace.transactions
               .where(id: transaction_ids, status: "pending", ai_status: "queued")
               .exists?
    end
  end
end
