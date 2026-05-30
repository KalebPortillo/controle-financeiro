require "test_helper"

# Integração entre sync e onboarding (RF22 Fatia 3):
# - SuggestJob NÃO dispara durante onboarding ativo
# - AnalyzeJob é enfileirado quando o sync termina com workspace em connecting
class BankConnections::OnboardingIntegrationTest < ActiveJob::TestCase
  setup do
    @workspace  = create(:workspace)
    @membership = create(:workspace_membership, workspace: @workspace)
    @connection = create(:bank_connection, workspace: @workspace, owner_membership: @membership)
    @account    = create(:account, workspace: @workspace, bank_connection: @connection,
                         owner_membership: @membership)
  end

  test "sync does not enqueue SuggestJob while onboarding is active" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })

    fake_tx = {
      id: "ext-1", amount: -50.0, date: Date.current.iso8601,
      description: "Compra", currency_code: "BRL", raw: { "id" => "ext-1" }
    }
    provider = FakeProvider.new(transactions: [ fake_tx ])

    assert_no_enqueued_jobs only: AiSuggestion::SuggestJob do
      BankConnections::Sync.call(connection: @connection, provider: provider)
    end
  end

  test "sync enqueues AnalyzeJob when workspace is in connecting" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })
    provider = FakeProvider.new(transactions: [])

    assert_enqueued_with(job: Onboarding::AnalyzeJob, args: [ @workspace.id ]) do
      BankConnections::Sync.call(connection: @connection, provider: provider)
    end

    assert_equal "analyzing", @workspace.reload.onboarding_state["status"]
  end

  test "sync does not enqueue AnalyzeJob when onboarding is already past connecting" do
    @workspace.update!(onboarding_state: { "status" => "completed" })
    provider = FakeProvider.new(transactions: [])

    assert_no_enqueued_jobs only: Onboarding::AnalyzeJob do
      BankConnections::Sync.call(connection: @connection, provider: provider)
    end
  end

  test "sync enqueues SuggestJob normally when no onboarding is active" do
    @workspace.update!(onboarding_state: { "status" => "completed" })

    fake_tx = {
      id: "ext-2", amount: -50.0, date: Date.current.iso8601,
      description: "Compra", currency_code: "BRL", raw: { "id" => "ext-2" }
    }
    provider = FakeProvider.new(transactions: [ fake_tx ])

    assert_enqueued_jobs 1, only: AiSuggestion::SuggestJob do
      BankConnections::Sync.call(connection: @connection, provider: provider)
    end
  end

  # RF9.1 — detecção de recorrentes roda ao fim do sync (fora do onboarding).
  test "sync enqueues Recurrences::DetectJob when onboarding is not active" do
    @workspace.update!(onboarding_state: { "status" => "completed" })
    provider = FakeProvider.new(transactions: [])

    assert_enqueued_with(job: Recurrences::DetectJob, args: [ @workspace.id ]) do
      BankConnections::Sync.call(connection: @connection, provider: provider)
    end
  end

  test "sync does not enqueue Recurrences::DetectJob during onboarding" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })
    provider = FakeProvider.new(transactions: [])

    assert_no_enqueued_jobs only: Recurrences::DetectJob do
      BankConnections::Sync.call(connection: @connection, provider: provider)
    end
  end

  class FakeProvider
    def initialize(transactions: [])
      @transactions = transactions
    end

    def list_transactions(**)
      @transactions
    end
  end
end
