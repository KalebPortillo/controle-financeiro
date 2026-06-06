require "test_helper"

class AiSuggestion::SuggestCategoriesJobTest < ActiveJob::TestCase
  setup do
    @workspace = create(:workspace)
    create(:tag, workspace: @workspace, name: "Alimentação")
    create(:tag, workspace: @workspace, name: "Transporte")
  end

  test "records suggested categories from the workspace's consolidated tags" do
    stub_provider([ { name: "Essenciais", tag_names: [ "Alimentação", "Transporte" ] } ])

    AiSuggestion::SuggestCategoriesJob.perform_now(@workspace.id)

    catalog = @workspace.suggested_categories.pending
    assert_equal [ "Essenciais" ], catalog.pluck(:name)
    assert_equal [ "Alimentação", "Transporte" ], catalog.first.tag_names
  end

  test "passes existing real + pending categories as exclusions to the provider" do
    create(:category, workspace: @workspace, name: "Moradia")
    @workspace.suggested_categories.create!(name: "Lazer", status: "pending", tag_names: [])
    provider = CaptureProvider.new([])
    stub_with(provider)

    AiSuggestion::SuggestCategoriesJob.perform_now(@workspace.id)

    assert_includes provider.captured_existing, "Moradia"
    assert_includes provider.captured_existing, "Lazer"
  end

  test "no-op when the workspace has no tags" do
    @workspace.tags.destroy_all
    stub_provider([ { name: "X", tag_names: [] } ])

    AiSuggestion::SuggestCategoriesJob.perform_now(@workspace.id)

    assert_empty @workspace.suggested_categories
  end

  test "does not re-suggest a category that already exists as real" do
    create(:category, workspace: @workspace, name: "Essenciais")
    stub_provider([ { name: "Essenciais", tag_names: [ "Alimentação" ] } ])

    AiSuggestion::SuggestCategoriesJob.perform_now(@workspace.id)

    assert_empty @workspace.suggested_categories
  end

  test "records ai_last_error and does not retry on quota" do
    stub_raises(AiProviders::ApiError.new("HTTP 429 depleted", reason: :quota))

    assert_enqueued_jobs 0, only: AiSuggestion::SuggestCategoriesJob do
      AiSuggestion::SuggestCategoriesJob.perform_now(@workspace.id)
    end
    assert_equal "quota", @workspace.reload.ai_error_payload[:reason]
  end

  test "clears a previous ai error on success" do
    @workspace.record_ai_error!(AiProviders::ApiError.new("old", reason: :quota))
    stub_provider([ { name: "Essenciais", tag_names: [ "Alimentação" ] } ])

    AiSuggestion::SuggestCategoriesJob.perform_now(@workspace.id)

    assert_nil @workspace.reload.ai_last_error
  end

  test "no-op when workspace missing" do
    assert_nothing_raised do
      AiSuggestion::SuggestCategoriesJob.perform_now("00000000-0000-0000-0000-000000000000")
    end
  end

  private

  def stub_provider(result)
    stub_with(FakeProvider.new(result))
  end

  def stub_raises(error)
    stub_with(RaisingProvider.new(error))
  end

  def stub_with(provider)
    klass = AiProviders::GeminiProvider
    klass.singleton_class.send(:alias_method, :__orig_new, :new) unless klass.singleton_class.method_defined?(:__orig_new)
    klass.singleton_class.send(:define_method, :new) { |**_| provider }
    @stubbed = true
  end

  teardown do
    next unless @stubbed
    klass = AiProviders::GeminiProvider
    klass.singleton_class.send(:remove_method, :new) if klass.singleton_class.method_defined?(:new)
    klass.singleton_class.send(:alias_method, :new, :__orig_new)
    klass.singleton_class.send(:remove_method, :__orig_new)
    @stubbed = false
  end

  class FakeProvider
    def initialize(result); @result = result; end
    def suggest_categories_from_tags(**_); @result; end
  end

  class CaptureProvider
    attr_reader :captured_existing
    def initialize(result); @result = result; @captured_existing = []; end
    def suggest_categories_from_tags(tag_names:, existing_categories: [])
      @captured_existing = existing_categories
      @result
    end
  end

  class RaisingProvider
    def initialize(error); @error = error; end
    def suggest_categories_from_tags(**_); raise @error; end
  end
end
