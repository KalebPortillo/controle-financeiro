require "test_helper"

class Onboarding::AnalyzeJobTest < ActiveJob::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
    @workspace.update!(onboarding_state: { "status" => "analyzing" })

    # Algumas transações pending pra IA analisar
    3.times do |i|
      create(:transaction, workspace: @workspace, account: @account,
             original_description: "MERCADO #{i}", status: "pending")
    end
  end

  test "discovery mode records suggested tags in the catalog and transitions to tagging" do
    stub_provider(
      tags: [ { name: "Mercado", rationale: "3 mercados", coverage: 3 } ],
      categories: []
    )

    Onboarding::AnalyzeJob.perform_now(@workspace.id)

    assert_equal "tagging", @workspace.reload.onboarding_state["status"]
    catalog = @workspace.suggested_tags.pending
    assert_equal [ "Mercado" ], catalog.pluck(:name)
    assert_equal 3, catalog.first.coverage
    # As sugestões NÃO ficam mais no jsonb (catálogo é fonte única).
    refute_includes @workspace.onboarding_state.keys, "suggested_tags"
  end

  test "additive mode keeps status and records new suggestions in the catalog" do
    @workspace.update!(onboarding_state: { "status" => "completed" })
    create(:tag, workspace: @workspace, name: "Mercado")

    stub_provider(
      tags: [ { name: "Padaria", rationale: "2 padarias", coverage: 2 } ],
      categories: []
    )

    Onboarding::AnalyzeJob.perform_now(@workspace.id, mode: "additive")

    assert_equal "completed", @workspace.reload.onboarding_state["status"], "status must NOT advance in additive mode"
    assert_equal [ "Padaria" ], @workspace.suggested_tags.pending.pluck(:name)
  end

  test "no-op when no pending transactions" do
    Transaction.where(workspace: @workspace).destroy_all
    stub_provider(tags: [], categories: [])

    Onboarding::AnalyzeJob.perform_now(@workspace.id)

    # Status não muda quando não há trabalho a fazer
    assert_equal "analyzing", @workspace.reload.onboarding_state["status"]
    assert_empty @workspace.suggested_tags
  end

  test "no-op when workspace missing" do
    assert_nothing_raised do
      Onboarding::AnalyzeJob.perform_now("00000000-0000-0000-0000-000000000000")
    end
  end

  # RF22 bug: se a IA falha de vez (timeout/erro), o onboarding NÃO pode ficar
  # preso em "analyzing". Após esgotar os retries, avança pra "tagging" com
  # sugestões vazias — o usuário cai no passo de tags e segue manualmente.
  test "after the provider keeps failing, the flow advances to tagging instead of staying stuck" do
    stub_failing_provider

    perform_enqueued_jobs do
      Onboarding::AnalyzeJob.perform_now(@workspace.id)
    rescue AiProviders::ApiError
      # o retry final relança; o que importa é o estado depois
    end

    assert_equal "tagging", @workspace.reload.onboarding_state["status"]
  end

  private

  def stub_provider(result)
    klass = AiProviders::GeminiProvider
    klass.singleton_class.send(:alias_method, :__orig_new, :new) unless klass.singleton_class.method_defined?(:__orig_new)
    klass.singleton_class.send(:define_method, :new) { |**_| FakeProvider.new(result) }
    @stubbed = true
  end

  def stub_failing_provider
    klass = AiProviders::GeminiProvider
    klass.singleton_class.send(:alias_method, :__orig_new, :new) unless klass.singleton_class.method_defined?(:__orig_new)
    klass.singleton_class.send(:define_method, :new) { |**_| FailingProvider.new }
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
    def suggest_onboarding_discovery(**_); @result; end
  end

  class FailingProvider
    def suggest_onboarding_discovery(**_)
      raise AiProviders::ApiError, "Gemini network error: Net::ReadTimeout"
    end
  end
end
