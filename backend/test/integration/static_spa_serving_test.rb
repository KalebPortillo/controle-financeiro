require "test_helper"

# Cobre o catch-all que entrega o `index.html` do SPA. A regressão que
# motivou este teste: `render file:` em API mode devolvia body vazio quando
# atendido pelo catch-all (mas funcionava pelo `root`) — só descobrimos em
# produção. Trocamos por `index_path.read` + `render plain:`.
class StaticSpaServingTest < ActionDispatch::IntegrationTest
  test "GET / serves the SPA index.html with HTML content type" do
    get "/", headers: { "Accept" => "text/html" }
    assert_response :ok
    assert_match(/text\/html/, response.media_type)
    assert response.body.length > 100, "expected the SPA shell, got #{response.body.length} bytes"
    assert_match(/<div id="root">/, response.body)
  end

  test "GET /qualquer-rota-spa também serve o index.html" do
    %w[/login /dashboard /workspaces/123].each do |path|
      get path, headers: { "Accept" => "text/html" }
      assert_response :ok, "expected 200 on #{path}, got #{response.status}"
      assert response.body.length > 100,
        "expected the SPA shell on #{path}, got #{response.body.length} bytes"
      assert_match(/<div id="root">/, response.body)
    end
  end

  test "GET /api/v1/health não é interceptado pelo catch-all" do
    get "/api/v1/health"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
  end

  test "catch-all não responde para requests XHR ou não-HTML" do
    get "/qualquer-coisa", headers: { "Accept" => "application/json" }
    # Sem rota match, Rails devolve 404 (não cai no SPA).
    assert_includes [ 404, 406 ], response.status
  end
end
