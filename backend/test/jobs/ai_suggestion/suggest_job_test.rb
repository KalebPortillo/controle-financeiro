require "test_helper"

class AiSuggestion::SuggestJobTest < ActiveJob::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
    @tx = create(:transaction, workspace: @workspace, account: @account,
                 original_description: "MERCADO ABC", status: "pending")
  end

  test "applies improved_title and ai_confidence" do
    stub_service(improved_title: "Mercado ABC", confidence: "high", source: "api")
    AiSuggestion::SuggestJob.perform_now(@tx.id)

    @tx.reload
    assert_equal "Mercado ABC", @tx.improved_title
    assert_equal 0.9, @tx.ai_confidence
  end

  test "persists ai_suggestion snapshot" do
    tag = create(:tag, workspace: @workspace, name: "Mercado")
    stub_service(
      improved_title: "Mercado ABC",
      suggested_tag_ids: [ tag.id ],
      confidence: "high",
      source: "api"
    )
    AiSuggestion::SuggestJob.perform_now(@tx.id)

    snapshot = @tx.reload.ai_suggestion
    assert_equal "Mercado ABC",     snapshot["title"]
    assert_equal [ tag.id ],        snapshot["tag_ids"]
    assert_equal [ "Mercado" ],     snapshot["tag_names"]
    assert_equal "high",            snapshot["confidence"]
    assert_equal "api",             snapshot["source"]
    assert snapshot["suggested_at"].present?
  end

  test "applies existing tags from suggested_tag_ids" do
    tag1 = create(:tag, workspace: @workspace, name: "Mercado")
    tag2 = create(:tag, workspace: @workspace, name: "Casa")
    stub_service(suggested_tag_ids: [ tag1.id, tag2.id ], confidence: "high", source: "api")

    AiSuggestion::SuggestJob.perform_now(@tx.id)

    assert_equal [ tag1.id, tag2.id ].sort, @tx.reload.tags.pluck(:id).sort
  end

  test "creates new tag when new_tag_suggestion is set and applies it" do
    stub_service(new_tag_suggestion: "Cashback", confidence: "medium", source: "api")

    assert_difference "Tag.count", 1 do
      AiSuggestion::SuggestJob.perform_now(@tx.id)
    end

    assert_equal [ "Cashback" ], @tx.reload.tags.pluck(:name)
  end

  test "creates multiple tags in onboarding mode" do
    stub_service(suggested_new_tags: [ "Mercado", "Alimentação" ],
                 confidence: "high", source: "api_onboarding")

    assert_difference "Tag.count", 2 do
      AiSuggestion::SuggestJob.perform_now(@tx.id)
    end

    assert_equal %w[Alimentação Mercado], @tx.reload.tags.pluck(:name).sort
  end

  test "skips already-consolidated transactions" do
    @tx.update!(status: "consolidated", consolidated_at: Time.current)
    stub_service(improved_title: "Mercado ABC", confidence: "high", source: "api")

    AiSuggestion::SuggestJob.perform_now(@tx.id)

    assert_nil @tx.reload.improved_title
  end

  test "skips when service returns fallback source" do
    stub_service(improved_title: nil, suggested_tag_ids: [], confidence: nil,
                 source: "fallback")

    AiSuggestion::SuggestJob.perform_now(@tx.id)

    @tx.reload
    assert_nil @tx.improved_title
    assert_nil @tx.ai_suggestion
  end

  test "does not crash when transaction is missing" do
    assert_nothing_raised do
      AiSuggestion::SuggestJob.perform_now("00000000-0000-0000-0000-000000000000")
    end
  end

  private

  # Substitui Service.call por uma stub que retorna o hash desejado, e
  # restaura no teardown. Sem mocha/rspec, usamos alias_method por classe
  # singleton.
  def stub_service(overrides = {})
    base = {
      improved_title: nil,
      suggested_tag_ids: [],
      new_tag_suggestion: nil,
      suggested_new_tags: [],
      confidence: nil,
      source: "api"
    }
    result = base.merge(overrides)

    sclass = AiSuggestion::Service.singleton_class
    sclass.send(:alias_method, :__original_call, :call)
    sclass.send(:define_method, :call) { |**_| result }
    @service_stubbed = true
  end

  teardown do
    next unless @service_stubbed
    sclass = AiSuggestion::Service.singleton_class
    sclass.send(:remove_method, :call) if sclass.method_defined?(:call)
    sclass.send(:alias_method, :call, :__original_call)
    sclass.send(:remove_method, :__original_call)
    @service_stubbed = false
  end
end
