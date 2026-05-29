require "test_helper"

class AiSuggestion::ServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
  end

  def make_transaction(description: "MERCADO EXTRA LTDA", metadata: {})
    create(:transaction,
           workspace: @workspace,
           account: @account,
           original_description: description,
           source_metadata: metadata,
           status: "pending")
  end

  # --- Learned rules take priority over API ---

  test "applies learned rule without calling the API" do
    tag = create(:tag, workspace: @workspace, name: "Mercado")
    create(:ai_learned_rule,
           workspace: @workspace,
           descriptor_pattern: "mercado extra ltda",
           improved_title: "Mercado Extra",
           tag_ids: [ tag.id ],
           last_seen_at: Time.current)

    tx = make_transaction
    result = AiSuggestion::Service.call(transaction: tx, provider: FakeProvider.new)

    assert_equal "Mercado Extra", result[:improved_title]
    assert_equal [ tag.id ], result[:suggested_tag_ids]
    assert_equal "high", result[:confidence]
    assert_equal "learned", result[:source]
  end

  # --- Normal mode: existing tags ---

  test "calls provider and returns suggested tag ids" do
    tag = create(:tag, workspace: @workspace, name: "Telefonia")
    provider = FakeProvider.new(
      suggest_result: { improved_title: "Vivo", suggested_tag_ids: [ tag.id ],
                        new_tag_suggestion: nil, confidence: "high" }
    )

    tx = make_transaction(description: "VIVO SERVICOS")
    result = AiSuggestion::Service.call(transaction: tx, provider: provider)

    assert_equal "Vivo", result[:improved_title]
    assert_includes result[:suggested_tag_ids], tag.id
    assert_equal "api", result[:source]
  end

  test "includes new_tag_suggestion when provider returns one" do
    create(:tag, workspace: @workspace, name: "Qualquer")
    provider = FakeProvider.new(
      suggest_result: { improved_title: "Novo Local", suggested_tag_ids: [],
                        new_tag_suggestion: "Lazer", confidence: "medium" }
    )

    tx = make_transaction
    result = AiSuggestion::Service.call(transaction: tx, provider: provider)

    assert_equal "Lazer", result[:new_tag_suggestion]
  end

  # --- Onboarding mode: no tags ---

  test "uses onboarding mode when workspace has no tags" do
    tx = make_transaction
    provider = FakeProvider.new(
      batch_result: [ { transaction_id: tx.id, improved_title: "Mercado Extra",
                       suggested_new_tags: [ "Mercado" ], confidence: "high" } ]
    )

    result = AiSuggestion::Service.call(transaction: tx, provider: provider)

    assert_equal "Mercado Extra", result[:improved_title]
    assert_equal [ "Mercado" ], result[:suggested_new_tags]
    assert_equal "api_onboarding", result[:source]
  end

  # --- Fallback when provider fails ---

  test "returns nil improved_title when provider raises" do
    create(:tag, workspace: @workspace, name: "Qualquer") # modo normal
    provider = FakeProvider.new(raises: RuntimeError.new("timeout"))

    tx = make_transaction
    result = AiSuggestion::Service.call(transaction: tx, provider: provider)

    assert_nil result[:improved_title]
    assert_equal [], result[:suggested_tag_ids]
    assert_nil result[:confidence]
    assert_equal "fallback", result[:source]
  end

  # Simple fake provider — no external calls
  class FakeProvider < AiProviders::Provider
    def initialize(suggest_result: nil, batch_result: nil, raises: nil)
      @suggest_result = suggest_result || { improved_title: nil, suggested_tag_ids: [], new_tag_suggestion: nil, confidence: nil }
      @batch_result   = batch_result   || []
      @raises         = raises
    end

    def suggest(context:, existing_tags:)
      raise @raises if @raises
      @suggest_result
    end

    def suggest_batch(transactions_context:)
      raise @raises if @raises
      @batch_result
    end
  end
end
