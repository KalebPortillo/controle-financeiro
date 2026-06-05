require "test_helper"

# Integração entre sync e onboarding (RF22):
# - SuggestJob NÃO dispara durante onboarding ativo
# - O sync NÃO toca no onboarding_state nem dispara o AnalyzeJob (F2): a análise
#   é iniciada explicitamente pelo usuário (clique em "Continuar" → advance para
#   analyzing). Isso desacopla a análise do sync e evita o passo preso.
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

  test "sync does NOT enqueue AnalyzeJob nor advance status (F2: analysis is user-triggered)" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })
    provider = FakeProvider.new(transactions: [])

    assert_no_enqueued_jobs only: Onboarding::AnalyzeJob do
      BankConnections::Sync.call(connection: @connection, provider: provider)
    end

    # O sync deixa o usuário em connecting — ele segue conectando contas/CSV e
    # só avança quando clica "Continuar".
    assert_equal "connecting", @workspace.reload.onboarding_state["status"]
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

  # RF11.1 — detecção de transferências internas também roda ao fim do sync.
  test "sync enqueues InternalTransfers::DetectJob when onboarding is not active" do
    @workspace.update!(onboarding_state: { "status" => "completed" })
    provider = FakeProvider.new(transactions: [])

    assert_enqueued_with(job: InternalTransfers::DetectJob, args: [ @workspace.id ]) do
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
