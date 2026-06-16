require "test_helper"

# Fan-out periódico (Solid Queue recurring): enfileira um SyncJob por conexão
# Pluggy elegível, sem o usuário clicar. Rede de segurança caso o webhook do
# Pluggy não chegue (RF1/RF21).
class BankConnections::ScheduledSyncJobTest < ActiveJob::TestCase
  # IDs de conexão pros quais um SyncJob foi enfileirado no bloco.
  def synced_ids
    yield
    enqueued_jobs.select { |j| j[:job] == BankConnections::SyncJob }
                 .map { |j| j[:args].first }
  end

  test "enqueues a SyncJob for connected pluggy connections" do
    conn = create(:bank_connection, status: "connected", last_sync_at: 2.hours.ago)

    ids = synced_ids { BankConnections::ScheduledSyncJob.perform_now }

    assert_equal [ conn.id ], ids
  end

  test "skips connections that are not connected (expired/error/syncing)" do
    create(:bank_connection, status: "expired", last_sync_at: 2.hours.ago)
    create(:bank_connection, status: "error", last_sync_at: 2.hours.ago)
    create(:bank_connection, status: "syncing", last_sync_at: 2.hours.ago)

    ids = synced_ids { BankConnections::ScheduledSyncJob.perform_now }

    assert_empty ids
  end

  test "skips connections synced too recently (min interval)" do
    create(:bank_connection, status: "connected", last_sync_at: 5.minutes.ago)

    ids = synced_ids { BankConnections::ScheduledSyncJob.perform_now }

    assert_empty ids
  end

  test "syncs a connection that never synced (last_sync_at nil)" do
    conn = create(:bank_connection, status: "connected", last_sync_at: nil)

    ids = synced_ids { BankConnections::ScheduledSyncJob.perform_now }

    assert_equal [ conn.id ], ids
  end

  test "skips connections of workspaces still in onboarding" do
    ws = create(:workspace, onboarding_state: { "status" => "analyzing" })
    create(:bank_connection, workspace: ws, status: "connected", last_sync_at: 2.hours.ago)

    ids = synced_ids { BankConnections::ScheduledSyncJob.perform_now }

    assert_empty ids
  end

  test "ignores manual (non-pluggy) connections" do
    create(:bank_connection, provider: "manual", status: "connected", last_sync_at: 2.hours.ago)

    ids = synced_ids { BankConnections::ScheduledSyncJob.perform_now }

    assert_empty ids
  end
end
