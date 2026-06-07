require "test_helper"

class AiSuggestion::ReanalyzeJobTest < ActiveJob::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
  end

  # Reúne os ids enviados aos BatchSuggestJob enfileirados durante o bloco.
  def batched_ids
    assert_enqueued_jobs 1, only: AiSuggestion::BatchSuggestJob do
      yield
    end
    enqueued_jobs.select { |j| j[:job] == AiSuggestion::BatchSuggestJob }
                 .flat_map { |j| j[:args].first }
  end

  test "enqueues a batch for pending transactions without improved_title" do
    tx = create(:transaction, workspace: @workspace, account: @account,
                status: "pending", improved_title: nil)

    ids = batched_ids { AiSuggestion::ReanalyzeJob.perform_now(@workspace.id) }
    assert_includes ids, tx.id
  end

  test "clears the ai_suggestion snapshot of eligible transactions so progress reflects the rerun" do
    # tx "analisada" mas sem título/tags (snapshot vazio do bug de truncamento):
    # é elegível (improved_title nil) e o snapshot deve ser zerado na reanálise.
    tx = create(:transaction, workspace: @workspace, account: @account,
                status: "pending", improved_title: nil,
                ai_suggestion: { "title" => nil, "tag_ids" => [] })

    AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)

    assert_nil tx.reload.ai_suggestion
  end

  test "re-queues failed transactions (ai_status failed → queued) and batches them" do
    failed = create(:transaction, workspace: @workspace, account: @account,
                    status: "pending", improved_title: "Posto", ai_confidence: 0.9, ai_status: "failed")
    failed.tags << create(:tag, workspace: @workspace) # tem título+conf+tags, só falhou

    ids = batched_ids { AiSuggestion::ReanalyzeJob.perform_now(@workspace.id) }
    assert_includes ids, failed.id
    assert_equal "queued", failed.reload.ai_status
  end

  test "does not touch transactions that are not eligible" do
    tagged = create(:transaction, workspace: @workspace, account: @account,
                    status: "pending", improved_title: "Mercado", ai_confidence: 0.9,
                    ai_suggestion: { "title" => "Mercado" })
    tagged.tags << create(:tag, workspace: @workspace)

    AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)

    assert_equal "Mercado", tagged.reload.ai_suggestion["title"] # snapshot preservado
  end

  test "enqueues a batch for low-confidence transactions" do
    tx = create(:transaction, workspace: @workspace, account: @account,
                status: "pending", improved_title: "ok", ai_confidence: 0.3)

    ids = batched_ids { AiSuggestion::ReanalyzeJob.perform_now(@workspace.id) }
    assert_includes ids, tx.id
  end

  test "enqueues a batch for transactions without tags" do
    tx = create(:transaction, workspace: @workspace, account: @account,
                status: "pending", improved_title: "Titulo OK", ai_confidence: 0.9)

    ids = batched_ids { AiSuggestion::ReanalyzeJob.perform_now(@workspace.id) }
    assert_includes ids, tx.id
  end

  test "ignores transactions that have title, high confidence and tags" do
    tx = create(:transaction, workspace: @workspace, account: @account,
                status: "pending", improved_title: "Titulo", ai_confidence: 0.9)
    tx.tags << create(:tag, workspace: @workspace)

    assert_no_enqueued_jobs only: AiSuggestion::BatchSuggestJob do
      AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)
    end
  end

  test "ignores non-pending transactions" do
    create(:transaction, workspace: @workspace, account: @account,
           status: "consolidated", improved_title: nil)

    assert_no_enqueued_jobs only: AiSuggestion::BatchSuggestJob do
      AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)
    end
  end

  test "ignores transactions from other workspaces" do
    other_workspace = create(:workspace)
    other_account   = create(:account, workspace: other_workspace)
    create(:transaction, workspace: other_workspace, account: other_account,
           status: "pending", improved_title: nil)

    assert_no_enqueued_jobs only: AiSuggestion::BatchSuggestJob do
      AiSuggestion::ReanalyzeJob.perform_now(@workspace.id)
    end
  end

  test "no-op when workspace does not exist" do
    assert_nothing_raised do
      AiSuggestion::ReanalyzeJob.perform_now("00000000-0000-0000-0000-000000000000")
    end
  end
end
