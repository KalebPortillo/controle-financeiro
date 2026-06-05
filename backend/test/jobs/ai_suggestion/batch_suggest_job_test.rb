require "test_helper"

# P2 — job de sugestão em lote. Persiste o resultado do BatchService em cada
# transação (improved_title, ai_confidence, snapshot, tags). A contagem de
# chamadas ao provider (1 por lote) é coberta em BatchServiceTest.
class AiSuggestion::BatchSuggestJobTest < ActiveJob::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
    @tx1 = create(:transaction, workspace: @workspace, account: @account,
                  original_description: "MERCADO ABC", status: "pending")
    @tx2 = create(:transaction, workspace: @workspace, account: @account,
                  original_description: "POSTO SHELL", status: "pending")
  end

  test "persists suggestions for every transaction in the batch" do
    stub_batch(
      @tx1.id => result(improved_title: "Mercado ABC", new_tag_suggestion: "Mercado", confidence: "high"),
      @tx2.id => result(improved_title: "Posto Shell", confidence: "medium")
    )
    AiSuggestion::BatchSuggestJob.perform_now([ @tx1.id, @tx2.id ])

    assert_equal "Mercado ABC", @tx1.reload.improved_title
    assert_equal 0.9, @tx1.ai_confidence
    assert @tx1.ai_suggestion.present?
    assert_includes @tx1.tags.pluck(:name), "Mercado"
    assert_equal "Posto Shell", @tx2.reload.improved_title
  end

  test "skips consolidated transactions" do
    @tx1.update!(status: "consolidated", consolidated_at: Time.current)
    stub_batch(@tx2.id => result(improved_title: "Posto Shell", confidence: "low"))
    AiSuggestion::BatchSuggestJob.perform_now([ @tx1.id, @tx2.id ])

    assert_nil @tx1.reload.improved_title
    assert_equal "Posto Shell", @tx2.reload.improved_title
  end

  test "does not crash on missing ids" do
    assert_nothing_raised do
      AiSuggestion::BatchSuggestJob.perform_now([ "00000000-0000-0000-0000-000000000000" ])
    end
  end

  private

  def result(overrides)
    { improved_title: nil, suggested_tag_ids: [], new_tag_suggestion: nil,
      suggested_new_tags: [], confidence: nil, source: "api" }.merge(overrides)
  end

  # Stub de BatchService.call → devolve o hash { tx_id => result } informado,
  # restaurado no teardown.
  def stub_batch(results)
    sclass = AiSuggestion::BatchService.singleton_class
    sclass.send(:alias_method, :__original_call, :call)
    sclass.send(:define_method, :call) { |**_| results }
    @batch_stubbed = true
  end

  teardown do
    next unless @batch_stubbed
    sclass = AiSuggestion::BatchService.singleton_class
    sclass.send(:remove_method, :call) if sclass.method_defined?(:call)
    sclass.send(:alias_method, :call, :__original_call)
    sclass.send(:remove_method, :__original_call)
    @batch_stubbed = false
  end
end
