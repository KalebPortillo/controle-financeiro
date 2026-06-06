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

  # --- Classificação de erro (camada de feedback) ---

  test "429 with depleted credits classifies as :quota (not retryable)" do
    body = { error: { code: 429, status: "RESOURCE_EXHAUSTED",
                      message: "Your prepayment credits are depleted." } }.to_json
    stub_request(:post, @url).to_return(status: 429, body: body)
    err = assert_raises(AiProviders::ApiError) { @provider.suggest_onboarding_discovery(transactions_context: []) }
    assert_equal :quota, err.reason
    refute err.retryable?
  end

  test "429 rate-limit classifies as :rate_limit (retryable)" do
    body = { error: { code: 429, status: "RESOURCE_EXHAUSTED",
                      message: "Quota exceeded: requests per minute" } }.to_json
    stub_request(:post, @url).to_return(status: 429, body: body)
    err = assert_raises(AiProviders::ApiError) { @provider.suggest_onboarding_discovery(transactions_context: []) }
    assert_equal :rate_limit, err.reason
    assert err.retryable?
  end

  test "5xx classifies as :unavailable" do
    stub_request(:post, @url).to_return(status: 503, body: "upstream down")
    err = assert_raises(AiProviders::ApiError) { @provider.suggest_onboarding_discovery(transactions_context: []) }
    assert_equal :unavailable, err.reason
  end

  test "network timeout classifies as :unavailable" do
    stub_request(:post, @url).to_timeout
    err = assert_raises(AiProviders::ApiError) { @provider.suggest_onboarding_discovery(transactions_context: []) }
    assert_equal :unavailable, err.reason
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
    prompt = @provider.send(:build_categories_prompt, [ "Alimentação", "Transporte" ], [])
    assert_match(/SOMENTE tags da lista/, prompt)
    assert_match(/Alimentação/, prompt)
  end

  test "categories prompt excludes already-existing categories and caps at 10" do
    prompt = @provider.send(:build_categories_prompt, [ "Alimentação" ], [ "Essenciais", "Lazer" ])
    assert_match(/Essenciais/, prompt)
    assert_match(/já existem/i, prompt)
    assert_match(/10/, prompt)
  end

  # --- Sugerir tags faltantes para uma categoria (só das candidatas) ---

  test "suggest_tags_for_category returns [] for empty candidates without calling the API" do
    assert_equal [], @provider.suggest_tags_for_category(
      category_name: "Casa", member_tag_names: [ "Aluguel" ], candidate_tag_names: []
    )
  end

  test "suggest_tags_for_category only returns names from the candidate list" do
    payload = { candidates: [ { content: { parts: [ { text: {
      tag_names: [ "Luz", "Água", "Inventada" ]
    }.to_json } ] } } ] }
    stub_request(:post, @url).to_return(status: 200, body: payload.to_json)

    result = @provider.suggest_tags_for_category(
      category_name: "Contas da casa", member_tag_names: [ "Aluguel" ],
      candidate_tag_names: [ "Luz", "Água", "Transporte" ]
    )
    assert_equal [ "Luz", "Água" ], result # "Inventada" descartada por não ser candidata
  end

  test "category tags prompt restricts to candidate tags" do
    prompt = @provider.send(:build_category_tags_prompt, "Casa", [ "Aluguel" ], [ "Luz", "Água" ])
    assert_match(/Casa/, prompt)
    assert_match(/SOMENTE/, prompt)
    assert_match(/Luz/, prompt)
  end

  test "suggest_categories_from_tags caps the result at 10" do
    cats = (1..15).map { |i| { name: "Cat#{i}", tag_names: [ "Alimentação" ] } }
    payload = { candidates: [ { content: { parts: [ { text: { categories: cats }.to_json } ] } } ] }
    stub_request(:post, @url).to_return(status: 200, body: payload.to_json)

    result = @provider.suggest_categories_from_tags(tag_names: [ "Alimentação" ])
    assert_equal 10, result.size
  end
end
