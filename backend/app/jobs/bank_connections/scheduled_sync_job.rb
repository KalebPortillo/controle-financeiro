module BankConnections
  # Fan-out periódico (Solid Queue recurring — ver config/recurring.yml):
  # enfileira um SyncJob por conexão Pluggy elegível pra puxar transações novas
  # sem o usuário clicar. Rede de segurança caso o webhook do Pluggy não chegue
  # (RF1/RF21). Reusa SyncJob (status syncing, tratamento de erro/expired,
  # notificação de falha) — não duplica lógica de sync.
  class ScheduledSyncJob < ApplicationJob
    queue_as :default

    # Não re-sincroniza se uma sync recente já rodou (manual ou cadência
    # anterior) — evita trabalho e chamadas redundantes ao Pluggy.
    MIN_INTERVAL = 50.minutes

    def perform
      eligible_connections.find_each do |connection|
        BankConnections::SyncJob.perform_later(connection.id)
      end
    end

    private

    # Conectadas, do Pluggy, fora de onboarding e não sincronizadas há pouco.
    # Pula expired/error (exigem reconexão do usuário) e syncing (já em curso).
    def eligible_connections
      BankConnection
        .where(provider: "pluggy", status: "connected")
        .where("last_sync_at IS NULL OR last_sync_at < ?", MIN_INTERVAL.ago)
        .where.not(workspace_id: onboarding_workspace_ids)
    end

    def onboarding_workspace_ids
      Workspace
        .where("onboarding_state ->> 'status' IN (?)", BankConnections::Sync::ONBOARDING_ACTIVE_STATUSES)
        .pluck(:id)
    end
  end
end
