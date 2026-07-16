require "test_helper"

# Defesa em profundidade contra CSRF (OriginVerification): request MUTANTE com
# header Origin de outro host → 403. GETs e requests sem Origin (webhooks,
# clients máquina→máquina) passam normalmente.
class OriginVerificationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    sign_in_as(@user)
  end

  test "POST com Origin de outro host é rejeitado com 403" do
    post "/api/v1/tags", params: { name: "Mercado" },
                         headers: { "Origin" => "https://evil.example.net" }
    assert_response :forbidden
    assert_equal "origin_mismatch", JSON.parse(response.body).dig("error", "code")
  end

  test "POST com Origin do próprio host passa" do
    post "/api/v1/tags", params: { name: "Mercado" },
                         headers: { "Origin" => "http://www.example.com" }
    assert_response :created
  end

  test "POST com Origin do mesmo host em outra porta passa (proxy do Vite em dev/E2E)" do
    post "/api/v1/tags", params: { name: "Mercado" },
                         headers: { "Origin" => "http://www.example.com:5173" }
    assert_response :created
  end

  test "POST com Origin 'null' (contexto sandbox) é rejeitado" do
    post "/api/v1/tags", params: { name: "Mercado" },
                         headers: { "Origin" => "null" }
    assert_response :forbidden
  end

  test "POST sem Origin passa (webhooks e clients não-browser)" do
    post "/api/v1/tags", params: { name: "Mercado" }
    assert_response :created
  end

  test "GET com Origin de outro host passa (não é mutante)" do
    get "/api/v1/tags", headers: { "Origin" => "https://evil.example.net" }
    assert_response :ok
  end
end
