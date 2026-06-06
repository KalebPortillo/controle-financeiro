require "test_helper"

class Categories::SuggestTagsJobTest < ActiveJob::TestCase
  setup do
    @workspace = create(:workspace)
    @category  = create(:category, workspace: @workspace, name: "Contas da casa")
    @member    = create(:tag, workspace: @workspace, name: "Aluguel")
    @category.tags << @member
    @luz   = create(:tag, workspace: @workspace, name: "Luz")
    @agua  = create(:tag, workspace: @workspace, name: "Água")
  end

  test "records pending suggestions for candidate tags the AI picks" do
    stub_provider([ "Luz", "Água" ])

    Categories::SuggestTagsJob.perform_now(@category.id)

    suggested = @category.category_tag_suggestions.pending.map { |s| s.tag.name }.sort
    assert_equal [ "Luz", "Água" ].sort, suggested
  end

  test "never suggests a tag already in the category" do
    stub_provider([ "Aluguel", "Luz" ]) # Aluguel já é membro → nem é candidata

    Categories::SuggestTagsJob.perform_now(@category.id)

    names = @category.category_tag_suggestions.pending.map { |s| s.tag.name }
    refute_includes names, "Aluguel"
    assert_includes names, "Luz"
  end

  test "no-op when there are no candidate tags" do
    @category.tags << [ @luz, @agua ] # tudo já está na categoria
    stub_provider([ "Luz" ])

    Categories::SuggestTagsJob.perform_now(@category.id)

    assert_empty @category.category_tag_suggestions
  end

  test "does not resurrect a dismissed suggestion" do
    @category.category_tag_suggestions.create!(tag: @luz, status: "dismissed")
    stub_provider([ "Luz" ])

    Categories::SuggestTagsJob.perform_now(@category.id)

    assert_equal "dismissed", @category.category_tag_suggestions.find_by(tag: @luz).status
  end

  test "records ai_last_error and does not retry on quota" do
    stub_raises(AiProviders::ApiError.new("HTTP 429 depleted", reason: :quota))

    assert_enqueued_jobs 0, only: Categories::SuggestTagsJob do
      Categories::SuggestTagsJob.perform_now(@category.id)
    end
    assert_equal "quota", @workspace.reload.ai_error_payload[:reason]
  end

  test "no-op when category missing" do
    assert_nothing_raised do
      Categories::SuggestTagsJob.perform_now("00000000-0000-0000-0000-000000000000")
    end
  end

  private

  def stub_provider(names)
    stub_with(FakeProvider.new(names))
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
    def initialize(names); @names = names; end
    def suggest_tags_for_category(category_name:, member_tag_names:, candidate_tag_names:)
      @names & candidate_tag_names
    end
  end

  class RaisingProvider
    def initialize(error); @error = error; end
    def suggest_tags_for_category(**_); raise @error; end
  end
end
