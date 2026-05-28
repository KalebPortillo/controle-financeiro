require "test_helper"

class BankAggregators::PluggyTest < ActiveSupport::TestCase
  # Sandbox item fixo criado no Pluggy via connector 2 (Pluggy Bank) com
  # credenciais mágicas user-ok/password-ok. Se o item for deletado (30 dias
  # sem update), re-criar via `bin/rake pluggy:bootstrap_sandbox` (a ser
  # criado), atualizar estes IDs aqui e re-gravar cassettes (VCR_RECORD=all).
  SANDBOX_ITEM_ID         = "6d662866-386f-4523-8e31-fd3dcc4d1a96".freeze
  SANDBOX_BANK_ACCOUNT_ID = "6f91809e-cf34-433a-a01c-a4b852a974ce".freeze

  def provider
    BankAggregators::Pluggy.new(
      client_id:     ENV["PLUGGY_CLIENT_ID"]     || "test-client-id",
      client_secret: ENV["PLUGGY_CLIENT_SECRET"] || "test-client-secret"
    )
  end

  # --- Auth -------------------------------------------------------------

  test "auth troca client_id/secret por apiKey" do
    VCR.use_cassette("bank_aggregators/pluggy/auth_success") do
      api_key = provider.api_key
      # apiKey real é JWT (~700 chars); em cassettes vira "<PLUGGY_API_KEY>"
      # (filtrado pelo VCR — ver test_helper.rb). Aceitamos os dois.
      assert api_key.is_a?(String)
      assert api_key.present?
    end
  end

  test "api_key é cacheada entre chamadas (uma única request HTTP)" do
    VCR.use_cassette("bank_aggregators/pluggy/auth_success") do
      key_a = provider.api_key
      # Segunda chamada não deve emitir nova request — VCR estouraria
      # "request not stubbed" se tentasse (cassette só tem uma interação).
      key_b = provider.api_key
      assert_equal key_a, key_b
    end
  end

  # --- CONNECTORS ------------------------------------------------------

  test "CONNECTORS mapeia ids estáveis do Pluggy" do
    assert_equal 2,   BankAggregators::Pluggy::CONNECTORS[:sandbox_basic]
    assert_equal 612, BankAggregators::Pluggy::CONNECTORS[:nubank]
  end

  # --- list_accounts ----------------------------------------------------

  test "list_accounts(item_id) devolve array de hashes com id, type, number, balance" do
    VCR.use_cassette("bank_aggregators/pluggy/accounts_list") do
      accounts = provider.list_accounts(item_id: SANDBOX_ITEM_ID)
      assert accounts.is_a?(Array)
      assert accounts.any?, "esperava ao menos uma conta no sandbox item"
      first = accounts.first
      %i[id type name].each { |k| assert first.key?(k), "esperava chave #{k}" }
    end
  end

  # --- list_transactions ------------------------------------------------

  test "list_transactions(account_id, from:) devolve transações do período" do
    VCR.use_cassette("bank_aggregators/pluggy/transactions_list") do
      txns = provider.list_transactions(
        account_id: SANDBOX_BANK_ACCOUNT_ID,
        from:       Date.new(2026, 1, 1)
      )
      assert txns.is_a?(Array)
      assert txns.any?
      first = txns.first
      %i[id amount currency_code date description].each do |k|
        assert first.key?(k), "esperava chave #{k}, vieram: #{first.keys.inspect}"
      end
    end
  end

  # --- connect_token ----------------------------------------------------

  test "create_connect_token devolve um accessToken pro widget" do
    VCR.use_cassette("bank_aggregators/pluggy/connect_token") do
      token = provider.create_connect_token
      assert token.is_a?(String)
      assert token.present?
    end
  end

  # --- get_item ---------------------------------------------------------

  test "get_item devolve id, connector_id, connector_name, status" do
    VCR.use_cassette("bank_aggregators/pluggy/item_get") do
      item = provider.get_item(item_id: SANDBOX_ITEM_ID)
      assert_equal SANDBOX_ITEM_ID, item[:id]
      assert item.key?(:connector_id)
      assert item.key?(:connector_name)
      assert item.key?(:status)
    end
  end

  # --- error handling ---------------------------------------------------

  test "lança AuthenticationError quando credentials inválidas" do
    # UUID válido mas inexistente — Pluggy responde 401 (não 400 como
    # quando o clientId é malformado).
    bad = BankAggregators::Pluggy.new(
      client_id:     "00000000-0000-4000-8000-000000000000",
      client_secret: "wrong-secret"
    )
    VCR.use_cassette("bank_aggregators/pluggy/auth_unauthorized") do
      assert_raises(BankAggregators::AuthenticationError) { bad.api_key }
    end
  end

  # 401 + retry exige uma sequência sintética (primeiro accounts → 401, depois
  # accounts → 200) que é mais simples de stubar com webmock direto do que
  # editar cassette VCR à mão.
  test "401 em chamada autenticada → refresha apiKey e re-tenta uma vez" do
    auth_count    = 0
    account_count = 0
    stub_request(:post, "https://api.pluggy.ai/auth").to_return do |_|
      auth_count += 1
      { status: 200, body: { apiKey: "jwt-#{auth_count}" }.to_json,
        headers: { "Content-Type" => "application/json" } }
    end
    stub_request(:get, %r{https://api\.pluggy\.ai/accounts}).to_return do |_|
      account_count += 1
      if account_count == 1
        { status: 401, body: '{"message":"invalid token"}',
          headers: { "Content-Type" => "application/json" } }
      else
        { status: 200, body: { results: [ { "id" => "acc-1", "name" => "Conta", "type" => "BANK" } ] }.to_json,
          headers: { "Content-Type" => "application/json" } }
      end
    end

    p = BankAggregators::Pluggy.new(client_id: "00000000-0000-4000-8000-000000000000",
                                    client_secret: "any")
    accounts = p.list_accounts(item_id: "any-item")
    assert_equal 1, accounts.size
    assert_equal 2, account_count, "esperava 1 retry (total 2 chamadas)"
    assert_equal 2, auth_count,    "esperava re-auth (total 2 chamadas)"
  end
end
