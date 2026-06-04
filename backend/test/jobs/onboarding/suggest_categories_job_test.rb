require "test_helper"

class Onboarding::SuggestCategoriesJobTest < ActiveJob::TestCase
  setup do
    @workspace = create(:workspace)
    @workspace.update!(onboarding_state: { "status" => "categorizing" })
    create(:tag, workspace: @workspace, name: "Alimentação")
    create(:tag, workspace: @workspace, name: "Transporte")
  end

  test "records suggested categories from the workspace's accepted tags" do
    stub_provider([ { name: "Essenciais", tag_names: [ "Alimentação", "Transporte" ] } ])

    Onboarding::SuggestCategoriesJob.perform_now(@workspace.id)

    catalog = @workspace.suggested_categories.pending
    assert_equal [ "Essenciais" ], catalog.pluck(:name)
    assert_equal [ "Alimentação", "Transporte" ], catalog.first.tag_names
  end

  test "no-op when the workspace has no tags" do
    @workspace.tags.destroy_all
    stub_provider([ { name: "X", tag_names: [] } ])

    Onboarding::SuggestCategoriesJob.perform_now(@workspace.id)

    assert_empty @workspace.suggested_categories
  end

  test "no-op when workspace missing" do
    assert_nothing_raised do
      Onboarding::SuggestCategoriesJob.perform_now("00000000-0000-0000-0000-000000000000")
    end
  end

  test "does not re-suggest a category that already exists as real" do
    create(:category, workspace: @workspace, name: "Essenciais")
    stub_provider([ { name: "Essenciais", tag_names: [ "Alimentação" ] } ])

    Onboarding::SuggestCategoriesJob.perform_now(@workspace.id)

    assert_empty @workspace.suggested_categories
  end

  private

  def stub_provider(result)
    klass = AiProviders::GeminiProvider
    klass.singleton_class.send(:alias_method, :__orig_new, :new) unless klass.singleton_class.method_defined?(:__orig_new)
    klass.singleton_class.send(:define_method, :new) { |**_| FakeProvider.new(result) }
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
end
