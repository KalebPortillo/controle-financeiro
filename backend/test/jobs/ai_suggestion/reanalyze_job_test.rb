require "test_helper"

class AiSuggestion::ReanalyzeJobTest < ActiveJob::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
  end

  test "enqueues SuggestJob for pending transactions without improved_title" do
    tx = create(:transaction, workspace: @workspace, account: @account,
                status: "pending", improved_title: nil)

    assert_enqueued_with(job: AiSuggestion::SuggestJob, args: [ tx.id ]) do
      AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)
    end
  end

  test "enqueues SuggestJob for low-confidence transactions" do
    tx = create(:transaction, workspace: @workspace, account: @account,
                status: "pending", improved_title: "ok", ai_confidence: 0.3)

    assert_enqueued_with(job: AiSuggestion::SuggestJob, args: [ tx.id ]) do
      AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)
    end
  end

  test "enqueues SuggestJob for transactions without tags" do
    tx = create(:transaction, workspace: @workspace, account: @account,
                status: "pending", improved_title: "Titulo OK", ai_confidence: 0.9)

    assert_enqueued_with(job: AiSuggestion::SuggestJob, args: [ tx.id ]) do
      AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)
    end
  end

  test "ignores transactions that have title, high confidence and tags" do
    tx = create(:transaction, workspace: @workspace, account: @account,
                status: "pending", improved_title: "Titulo", ai_confidence: 0.9)
    tx.tags << create(:tag, workspace: @workspace)

    assert_no_enqueued_jobs only: AiSuggestion::SuggestJob do
      AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)
    end
  end

  test "ignores non-pending transactions" do
    create(:transaction, workspace: @workspace, account: @account,
           status: "consolidated", improved_title: nil)

    assert_no_enqueued_jobs only: AiSuggestion::SuggestJob do
      AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)
    end
  end

  test "ignores transactions from other workspaces" do
    other_workspace = create(:workspace)
    other_account   = create(:account, workspace: other_workspace)
    create(:transaction, workspace: other_workspace, account: other_account,
           status: "pending", improved_title: nil)

    assert_no_enqueued_jobs only: AiSuggestion::SuggestJob do
      AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)
    end
  end

  test "no-op when workspace does not exist" do
    assert_nothing_raised do
      AiSuggestion::ReanalyzeJob.perform_now("00000000-0000-0000-0000-000000000000")
    end
  end
end
