require "test_helper"

# Config pública lida pelo frontend no boot. Decide sandbox-vs-real por
# AMBIENTE (runtime/RAILS_ENV), porque staging e produção rodam a MESMA imagem
# — o flag não pode ser de build-time.
class AppConfigTest < ActionDispatch::IntegrationTest
  test "endpoint expõe a config do ambiente atual (test → sandbox)" do
    get "/api/v1/app_config", headers: { "Accept" => "application/json" }

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal Rails.env.to_s, body["environment"]
    assert_equal true,  body.dig("pluggy", "include_sandbox")
    assert_equal [ 2 ], body.dig("pluggy", "connector_ids")
  end

  test "config_for(staging): sandbox ligado + whitelist de conectores de teste" do
    cfg = Api::V1::AppConfigController.config_for("staging")

    assert_equal "staging", cfg[:environment]
    assert_equal true,  cfg[:pluggy][:include_sandbox]
    assert_equal [ 2 ], cfg[:pluggy][:connector_ids]
  end

  test "config_for(production): sem sandbox e sem whitelist (só bancos reais)" do
    cfg = Api::V1::AppConfigController.config_for("production")

    assert_equal "production", cfg[:environment]
    assert_equal false, cfg[:pluggy][:include_sandbox]
    assert_nil cfg[:pluggy][:connector_ids]
  end
end
