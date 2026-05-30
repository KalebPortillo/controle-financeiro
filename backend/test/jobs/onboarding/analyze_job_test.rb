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

  test "discovery mode persists suggested tags and categories, transitions to tagging" do
    stub_provider(
      tags: [ { name: "Mercado", rationale: "3 mercados", coverage: 3 } ],
      categories: [ { name: "Alimentação", tag_names: [ "Mercado" ] } ]
    )

    Onboarding::AnalyzeJob.perform_now(@workspace.id)

    state = @workspace.reload.onboarding_state
    assert_equal "tagging", state["status"]
    assert_equal 1, state["suggested_tags"].size
    assert_equal "Mercado", state["suggested_tags"].first["name"]
    assert_equal 1, state["suggested_categories"].size
  end

  test "additive mode keeps status and stores new suggestions" do
    @workspace.update!(onboarding_state: { "status" => "completed" })
    create(:tag, workspace: @workspace, name: "Mercado")
    create(:category, workspace: @workspace, name: "Alimentação")

    stub_provider(
      tags: [ { name: "Padaria", rationale: "2 padarias", coverage: 2 } ],
      categories: []
    )

    Onboarding::AnalyzeJob.perform_now(@workspace.id, mode: "additive")

    state = @workspace.reload.onboarding_state
    assert_equal "completed", state["status"], "status must NOT advance in additive mode"
    assert_equal "Padaria", state["suggested_tags"].first["name"]
  end

  test "no-op when no pending transactions" do
    Transaction.where(workspace: @workspace).destroy_all
    stub_provider(tags: [], categories: [])

    Onboarding::AnalyzeJob.perform_now(@workspace.id)

    state = @workspace.reload.onboarding_state
    # Status não muda quando não há trabalho a fazer
    assert_equal "analyzing", state["status"]
    refute_includes state.keys, "suggested_tags"
  end

  test "no-op when workspace missing" do
    assert_nothing_raised do
      Onboarding::AnalyzeJob.perform_now("00000000-0000-0000-0000-000000000000")
    end
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
    def suggest_onboarding_discovery(**_); @result; end
  end
end
