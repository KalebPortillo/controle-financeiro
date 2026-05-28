require "test_helper"

# Cobre o catch-all que entrega o `index.html` do SPA. A regressão que
# motivou este teste: `render file:` em API mode devolvia body vazio quando
# atendido pelo catch-all (mas funcionava pelo `root`) — só descobrimos em
# produção. Trocamos por `index_path.read` + `render plain:`.
#
# Em CI o frontend não está buildado (test job não roda `npm run build`), então
# criamos um SPA shell mínimo no setup pra exercitar o controller. Em dev
# local o arquivo real costuma estar no lugar — o setup faz backup e
# restaura.
class StaticSpaServingTest < ActionDispatch::IntegrationTest
  SHELL = <<~HTML
    <!doctype html>
    <html><body><div id="root">spa-shell-fixture-content-padded-pra-passar-do-cutoff-de-100-bytes</div></body></html>
  HTML

  # Garante o fixture uma vez antes da suíte. NÃO deletamos no teardown porque
  # `public/index.html` é um arquivo único no disco, compartilhado por TODOS os
  # workers paralelos — deletar no meio do teste de outro worker causa 404
  # intermitente. Escrever é idempotente (mesmo conteúdo), ler é sempre não-vazio.
  def ensure_spa_shell
    path = Rails.public_path.join("index.html")
    FileUtils.mkdir_p(path.dirname)
    path.write(SHELL) unless path.exist? && path.read.include?('<div id="root">')
  end

  setup { ensure_spa_shell }

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
