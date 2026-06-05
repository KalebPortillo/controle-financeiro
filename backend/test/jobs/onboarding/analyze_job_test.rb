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

  # Erro de IA fica TRANSPARENTE pro usuário (camada de feedback): em vez de
  # avançar em silêncio, registra o erro no workspace e mantém "analyzing" — a UI
  # mostra o card amigável com "Continuar manualmente".
  test "a transient failure records the ai error and keeps analyzing" do
    stub_failing_provider

    perform_enqueued_jobs do
      Onboarding::AnalyzeJob.perform_now(@workspace.id)
    rescue AiProviders::ApiError
      # o retry final relança; o que importa é o estado depois
    end

    @workspace.reload
    assert_equal "analyzing", @workspace.onboarding_state["status"]
    assert_equal "unavailable", @workspace.ai_error_payload[:reason]
  end

  test "a quota error is recorded without burning the 5 retries" do
    stub_quota_provider

    assert_enqueued_jobs 0, only: Onboarding::AnalyzeJob do
      Onboarding::AnalyzeJob.perform_now(@workspace.id) # quota não re-tenta
    end

    @workspace.reload
    assert_equal "analyzing", @workspace.onboarding_state["status"]
    assert_equal "quota", @workspace.ai_error_payload[:reason]
  end

  test "a successful analysis clears a previously recorded ai error" do
    @workspace.record_ai_error!(AiProviders::ApiError.new("old", reason: :quota))
    stub_provider(tags: [ { name: "Mercado", rationale: "x", coverage: 1 } ], categories: [])

    Onboarding::AnalyzeJob.perform_now(@workspace.id)

    assert_nil @workspace.reload.ai_last_error
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

  def stub_quota_provider
    klass = AiProviders::GeminiProvider
    klass.singleton_class.send(:alias_method, :__orig_new, :new) unless klass.singleton_class.method_defined?(:__orig_new)
    klass.singleton_class.send(:define_method, :new) { |**_| QuotaProvider.new }
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
      raise AiProviders::ApiError.new("Gemini network error: Net::ReadTimeout", reason: :unavailable)
    end
  end

  class QuotaProvider
    def suggest_onboarding_discovery(**_)
      raise AiProviders::ApiError.new("Gemini HTTP 429: depleted", reason: :quota)
    end
  end
end
