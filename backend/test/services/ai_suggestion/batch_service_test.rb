require "test_helper"

# P2 — pipeline de sugestão em LOTE. Aplica regras aprendidas por tx (sem API) e
# manda só o resto numa ÚNICA chamada ao provider. Mapeia o resultado por tx.
class AiSuggestion::BatchServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
  end

  def make_tx(description)
    create(:transaction, workspace: @workspace, account: @account,
           original_description: description, status: "pending")
  end

  test "sends all transactions to the provider in a single call" do
    create(:tag, workspace: @workspace, name: "Alimentação") # workspace tem tags → modo inbox
    tx1 = make_tx("MERCADO ABC")
    tx2 = make_tx("POSTO SHELL")
    provider = FakeBatchProvider.new(inbox_result: [
      { transaction_id: tx1.id, improved_title: "Mercado ABC", suggested_tag_ids: [], new_tag_suggestion: "Mercado", confidence: "high" },
      { transaction_id: tx2.id, improved_title: "Posto Shell", suggested_tag_ids: [], new_tag_suggestion: "Transporte", confidence: "medium" }
    ])

    results = AiSuggestion::BatchService.call(transactions: [ tx1, tx2 ], provider: provider)

    assert_equal 1, provider.inbox_calls
    assert_equal "Mercado ABC", results[tx1.id][:improved_title]
    assert_equal "api", results[tx1.id][:source]
    assert_equal "Posto Shell", results[tx2.id][:improved_title]
  end

  test "applies learned rules without sending those to the API" do
    create(:tag, workspace: @workspace, name: "Qualquer")
    rule_tag = create(:tag, workspace: @workspace, name: "Mercado")
    create(:ai_learned_rule, workspace: @workspace,
           descriptor_pattern: "mercado abc", improved_title: "Mercado ABC",
           tag_ids: [ rule_tag.id ], last_seen_at: Time.current)

    learned = make_tx("MERCADO ABC")
    fresh   = make_tx("POSTO SHELL")
    provider = FakeBatchProvider.new(inbox_result: [
      { transaction_id: fresh.id, improved_title: "Posto Shell", suggested_tag_ids: [], new_tag_suggestion: "Transporte", confidence: "medium" }
    ])

    results = AiSuggestion::BatchService.call(transactions: [ learned, fresh ], provider: provider)

    assert_equal 1, provider.inbox_calls
    assert_equal [ fresh.id ], provider.last_context_ids
    assert_equal "learned", results[learned.id][:source]
    assert_equal "Mercado ABC", results[learned.id][:improved_title]
    assert_equal "api", results[fresh.id][:source]
  end

  test "does not call the API when every transaction matches a learned rule" do
    create(:ai_learned_rule, workspace: @workspace,
           descriptor_pattern: "mercado abc", improved_title: "Mercado ABC",
           tag_ids: [], last_seen_at: Time.current)
    learned = make_tx("MERCADO ABC")
    provider = FakeBatchProvider.new

    results = AiSuggestion::BatchService.call(transactions: [ learned ], provider: provider)

    assert_equal 0, provider.inbox_calls
    assert_equal "learned", results[learned.id][:source]
  end

  test "uses onboarding batch when the workspace has no tags" do
    tx = make_tx("MERCADO ABC")
    provider = FakeBatchProvider.new(onboarding_result: [
      { transaction_id: tx.id, improved_title: "Mercado ABC", suggested_new_tags: [ "Mercado" ], confidence: "high" }
    ])

    results = AiSuggestion::BatchService.call(transactions: [ tx ], provider: provider)

    assert_equal 1, provider.onboarding_calls
    assert_equal 0, provider.inbox_calls
    assert_equal "api_onboarding", results[tx.id][:source]
    assert_equal [ "Mercado" ], results[tx.id][:suggested_new_tags]
  end

  test "falls back per transaction when the provider raises" do
    create(:tag, workspace: @workspace, name: "Qualquer")
    tx = make_tx("MERCADO ABC")
    provider = FakeBatchProvider.new(raises: RuntimeError.new("boom"))

    results = AiSuggestion::BatchService.call(transactions: [ tx ], provider: provider)

    assert_equal "fallback", results[tx.id][:source]
  end

  test "re-raises on 429 so the job can retry the whole batch" do
    create(:tag, workspace: @workspace, name: "Qualquer")
    tx = make_tx("MERCADO ABC")
    provider = FakeBatchProvider.new(raises: AiProviders::ApiError.new("Gemini HTTP 429: rate"))

    assert_raises(AiProviders::ApiError) do
      AiSuggestion::BatchService.call(transactions: [ tx ], provider: provider)
    end
  end

  class FakeBatchProvider < AiProviders::Provider
    attr_reader :inbox_calls, :onboarding_calls, :last_context_ids

    def initialize(inbox_result: [], onboarding_result: [], raises: nil)
      @inbox_result      = inbox_result
      @onboarding_result = onboarding_result
      @raises            = raises
      @inbox_calls       = 0
      @onboarding_calls  = 0
      @last_context_ids  = []
    end

    def suggest_inbox_batch(transactions_context:, existing_tags:)
      raise @raises if @raises
      @inbox_calls += 1
      @last_context_ids = transactions_context.map { |c| c[:id] }
      @inbox_result
    end

    def suggest_batch(transactions_context:)
      raise @raises if @raises
      @onboarding_calls += 1
      @last_context_ids = transactions_context.map { |c| c[:id] }
      @onboarding_result
    end
  end
end
