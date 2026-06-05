require "test_helper"

class AiProviders::GeminiProviderTest < ActiveSupport::TestCase
  setup do
    @provider = AiProviders::GeminiProvider.new(api_key: "test-key", model: "gemini-2.5-flash")
    @url = %r{https://generativelanguage\.googleapis\.com/v1beta/models/.+:generateContent}
  end

  # Performance: thinking desligado + saída limitada reduzem latência e tokens.
  test "request disables thinking and caps output tokens" do
    captured = nil
    stub_request(:post, @url).with { |req| captured = JSON.parse(req.body); true }
                             .to_return(status: 200, body: { candidates: [] }.to_json)
    @provider.suggest_categories_from_tags(tag_names: [ "Alimentação" ])

    gen = captured["generationConfig"]
    assert_equal 0, gen.dig("thinkingConfig", "thinkingBudget")
    assert_operator gen["maxOutputTokens"], :>, 0
    assert_equal "application/json", gen["responseMimeType"]
  end

  # --- Inbox em lote (P2): 1 chamada classifica várias transações com as tags
  #     existentes do workspace, devolvendo uma entrada por transaction_id. ---

  test "suggest_inbox_batch returns one entry per transaction mapped by id" do
    payload = { candidates: [ { content: { parts: [ { text: [
      { transaction_id: "a", improved_title: "Mercado Extra",
        suggested_tag_ids: [ "t1" ], new_tag_suggestion: nil, confidence: "high" },
      { transaction_id: "b", improved_title: "Posto Shell",
        suggested_tag_ids: [], new_tag_suggestion: "Transporte", confidence: "medium" }
    ].to_json } ] } } ] }
    stub_request(:post, @url).to_return(status: 200, body: payload.to_json)

    result = @provider.suggest_inbox_batch(
      transactions_context: [ { id: "a", description: "MERCADO" }, { id: "b", description: "POSTO" } ],
      existing_tags: [ { id: "t1", name: "Alimentação" } ]
    )

    assert_equal 2, result.size
    a = result.find { |r| r[:transaction_id] == "a" }
    assert_equal "Mercado Extra", a[:improved_title]
    assert_equal [ "t1" ], a[:suggested_tag_ids]
    b = result.find { |r| r[:transaction_id] == "b" }
    assert_equal "Transporte", b[:new_tag_suggestion]
    assert_equal "medium", b[:confidence]
  end

  test "inbox batch prompt lists existing tags and carries taxonomy guidance" do
    prompt = @provider.send(:build_inbox_batch_prompt,
                            [ { id: "1", description: "UBER" } ],
                            [ { id: "t1", name: "Transporte" } ])
    assert_match(/Transporte/, prompt)
    assert_match(/TEMAS AMPLOS/, prompt)
    assert_match(/Priorize sempre tags existentes/, prompt)
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

  # A4 — a IA deve sugerir temas amplos, não estabelecimentos. Garante que a
  # diretriz de taxonomia entra nos prompts de descoberta e da inbox.
  test "discovery prompt instructs broad themes, not merchant names" do
    prompt = @provider.send(:build_discovery_prompt, [ { id: "1", description: "NETFLIX" } ], [], [])
    assert_match(/TEMAS AMPLOS/, prompt)
    assert_match(/Assinaturas/, prompt)
    assert_match(/NUNCA use nome de empresa/, prompt)
    refute_match(/Tags são granulares/, prompt)
  end

  test "inbox onboarding prompt also carries the broad-theme guidance" do
    prompt = @provider.send(:build_onboarding_prompt, [ { id: "1", description: "SPOTIFY" } ])
    assert_match(/TEMAS AMPLOS/, prompt)
    assert_match(/Alimentação/, prompt)
  end

  # B-cat-2 — 2ª análise: categorias a partir das tags aceitas.
  test "suggest_categories_from_tags returns [] for empty tag list without calling the API" do
    assert_equal [], @provider.suggest_categories_from_tags(tag_names: [])
  end

  test "suggest_categories_from_tags parses categories grouping the given tags" do
    payload = { candidates: [ { content: { parts: [ { text: {
      categories: [ { name: "Essenciais", tag_names: [ "Alimentação", "Contas da casa" ] } ]
    }.to_json } ] } } ] }
    stub_request(:post, @url).to_return(status: 200, body: payload.to_json)

    result = @provider.suggest_categories_from_tags(tag_names: [ "Alimentação", "Contas da casa", "Lazer" ])
    assert_equal "Essenciais", result.first[:name]
    assert_equal [ "Alimentação", "Contas da casa" ], result.first[:tag_names]
  end

  test "suggest_categories_from_tags wraps network timeout as ApiError" do
    stub_request(:post, @url).to_timeout
    assert_raises(AiProviders::ApiError) do
      @provider.suggest_categories_from_tags(tag_names: [ "Alimentação" ])
    end
  end

  test "categories prompt restricts to the provided tags" do
    prompt = @provider.send(:build_categories_prompt, [ "Alimentação", "Transporte" ])
    assert_match(/SOMENTE tags da lista/, prompt)
    assert_match(/Alimentação/, prompt)
  end
end
