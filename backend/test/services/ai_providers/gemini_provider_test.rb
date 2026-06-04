require "test_helper"

class AiProviders::GeminiProviderTest < ActiveSupport::TestCase
  setup do
    @provider = AiProviders::GeminiProvider.new(api_key: "test-key", model: "gemini-2.5-flash")
    @url = %r{https://generativelanguage\.googleapis\.com/v1beta/models/.+:generateContent}
  end

  test "raises ConfigurationError when api key is blank" do
    provider = AiProviders::GeminiProvider.new(api_key: "", model: "gemini-2.5-flash")
    assert_raises(AiProviders::ConfigurationError) do
      provider.suggest_onboarding_discovery(transactions_context: [])
    end
  end

  test "read timeout becomes an ApiError so the job can retry (RF22 bug)" do
    stub_request(:post, @url).to_timeout
    assert_raises(AiProviders::ApiError) do
      @provider.suggest_onboarding_discovery(transactions_context: [ { id: "1", description: "X" } ])
    end
  end

  test "connection reset becomes an ApiError" do
    stub_request(:post, @url).to_raise(Errno::ECONNRESET)
    assert_raises(AiProviders::ApiError) do
      @provider.suggest_onboarding_discovery(transactions_context: [])
    end
  end

  test "non-success HTTP status raises ApiError" do
    stub_request(:post, @url).to_return(status: 503, body: "upstream down")
    assert_raises(AiProviders::ApiError) do
      @provider.suggest_onboarding_discovery(transactions_context: [])
    end
  end

  test "parses a successful discovery response" do
    payload = {
      candidates: [ { content: { parts: [ { text: {
        tags: [ { name: "Mercado", rationale: "8 compras", coverage: 8 } ],
        categories: [ { name: "Alimentação", tag_names: [ "Mercado" ] } ]
      }.to_json } ] } } ]
    }
    stub_request(:post, @url).to_return(status: 200, body: payload.to_json)

    result = @provider.suggest_onboarding_discovery(transactions_context: [ { id: "1", description: "MERCADO" } ])
    assert_equal "Mercado", result[:tags].first[:name]
    assert_equal "Alimentação", result[:categories].first[:name]
  end
end
