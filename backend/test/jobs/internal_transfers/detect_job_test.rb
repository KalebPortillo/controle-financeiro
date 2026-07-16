require "test_helper"

# Wrapper assíncrono do InternalTransfers::Detect (RF11.1) — disparado ao fim
# do sync. O contrato do JOB: delegar pro service e tolerar workspace apagado
# entre enqueue e perform.
class InternalTransfers::DetectJobTest < ActiveJob::TestCase
  test "detecta o par débito/crédito e cria a transferência interna" do
    workspace = create(:workspace)
    acc_a = create(:account, workspace: workspace)
    acc_b = create(:account, workspace: workspace)
    debit  = create(:transaction, workspace: workspace, account: acc_a, direction: "debit",
                    amount_cents: 50_000, status: "consolidated", occurred_at: Date.current)
    credit = create(:transaction, workspace: workspace, account: acc_b, direction: "credit",
                    amount_cents: 50_000, status: "consolidated", occurred_at: Date.current + 1)

    assert_difference -> { InternalTransfer.count }, 1 do
      InternalTransfers::DetectJob.perform_now(workspace.id)
    end
    assert InternalTransfer.exists?(debit_transaction: debit, credit_transaction: credit)
  end

  test "workspace apagado entre enqueue e perform → no-op" do
    assert_nothing_raised do
      InternalTransfers::DetectJob.perform_now(SecureRandom.uuid)
    end
  end
end
