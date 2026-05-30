require "test_helper"

class Recurrences::DetectJobTest < ActiveJob::TestCase
  test "chama o serviço de detecção para o workspace" do
    workspace = create(:workspace)
    account   = create(:account, workspace: workspace)
    3.times do |i|
      create(:transaction, workspace: workspace, account: account,
             original_description: "NETFLIX", amount_cents: 5990,
             occurred_at: Date.new(2026, 1, 10) + (i * 30),
             status: "consolidated", consolidated_at: Time.current)
    end

    assert_difference -> { workspace.recurrences.count }, 1 do
      Recurrences::DetectJob.perform_now(workspace.id)
    end
  end

  test "não explode se o workspace não existir" do
    assert_nothing_raised { Recurrences::DetectJob.perform_now("00000000-0000-0000-0000-000000000000") }
  end
end
