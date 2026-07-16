require "test_helper"

class AuthFlowTest < ActionDispatch::IntegrationTest
  # ---- Callback (signup + login) ---------------------------------------

  test "google callback creates a new user and signs them in" do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-new-1",
      info: { email: "new@example.com", name: "New User", image: nil }
    )

    assert_difference "User.count", 1 do
      assert_difference "Workspace.count", 1 do
        get "/api/v1/auth/google_oauth2/callback"
      end
    end

    # Após o callback o frontend é redirecionado pra raiz; a sessão fica setada.
    assert_response :redirect
    follow_redirect!

    get "/api/v1/sessions/current"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "new@example.com",       body.dig("user", "email")
    assert_equal "New User",              body.dig("user", "name")
    assert_equal 1,                        body["workspaces"].size
    assert_equal "New User's workspace",  body.dig("workspaces", 0, "name")
  end

  test "session cookie is persistent (has an expiry), so the user stays logged in" do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-persist",
      info: { email: "persist@example.com", name: "Persist", image: nil }
    )
    get "/api/v1/auth/google_oauth2/callback"

    set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
    session_line = set_cookie.lines.find { |l| l.include?("_controle_financeiro_session") }
    assert session_line, "esperava o cookie de sessão no Set-Cookie"
    # Cookie persistente = tem expires/max-age (não é cookie de sessão de browser).
    assert_match(/expires=|max-age=/i, session_line,
                 "cookie de sessão deve ter validade (expire_after) pra não deslogar toda hora")
  end

  test "google callback for existing user does not create a duplicate" do
    existing = create(:user, google_uid: "google-existing", email: "anna@example.com")

    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-existing",
      info: { email: "anna@example.com", name: "Anna", image: nil }
    )

    assert_no_difference "User.count" do
      get "/api/v1/auth/google_oauth2/callback"
    end

    get "/api/v1/sessions/current"
    body = JSON.parse(response.body)
    assert_equal existing.id, body.dig("user", "id")
  end

  test "google callback failure redirects with error" do
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials

    get "/api/v1/auth/google_oauth2/callback"
    assert_response :redirect
    # Sessão NÃO foi populada.
    get "/api/v1/sessions/current"
    assert_response :unauthorized
  end

  # ---- Request phase (anti login-CSRF) -----------------------------------

  test "request phase aceita POST com Origin do próprio host" do
    post "/api/v1/auth/google_oauth2", headers: { "Origin" => "http://www.example.com" }
    assert_response :redirect
    assert_match %r{/api/v1/auth/google_oauth2/callback}, response.location
  end

  test "request phase rejeita POST com Origin de outro host (login CSRF)" do
    post "/api/v1/auth/google_oauth2", headers: { "Origin" => "https://evil.example.net" }
    assert_response :redirect
    assert_match "auth_error", response.location
  end

  test "request phase rejeita POST sem Origin (browser sempre manda em POST)" do
    post "/api/v1/auth/google_oauth2"
    assert_response :redirect
    assert_match "auth_error", response.location
  end

  test "request phase não inicia OAuth via GET (só POST)" do
    get "/api/v1/auth/google_oauth2"
    # O middleware ignora o GET (allowed_request_methods = [:post]); a request
    # cai no catch-all do SPA em vez de redirecionar pro fluxo OAuth.
    assert_not_equal 302, response.status
  end

  # ---- Allowlist de emails -----------------------------------------------

  test "google callback rejects email not in ALLOWED_EMAILS" do
    with_allowed_emails("allowed@example.com") do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "google-blocked",
        info: { email: "blocked@other.com", name: "Blocked", image: nil }
      )

      assert_no_difference "User.count" do
        get "/api/v1/auth/google_oauth2/callback"
      end

      assert_response :redirect
      assert_match "unauthorized_email", response.location
      get "/api/v1/sessions/current"
      assert_response :unauthorized
    end
  end

  test "google callback allows email in ALLOWED_EMAILS" do
    with_allowed_emails("kaleb@ferreri.co,wife@example.com") do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "google-allowed",
        info: { email: "kaleb@ferreri.co", name: "Kaleb", image: nil }
      )

      assert_difference "User.count", 1 do
        get "/api/v1/auth/google_oauth2/callback"
      end

      follow_redirect!
      get "/api/v1/sessions/current"
      assert_response :ok
    end
  end

  test "google callback allows any email when ALLOWED_EMAILS is not set (fora de production)" do
    with_env("ALLOWED_EMAILS" => nil) do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "google-anyone",
        info: { email: "anyone@anywhere.com", name: "Anyone", image: nil }
      )

      assert_difference "User.count", 1 do
        get "/api/v1/auth/google_oauth2/callback"
      end
    end
  end

  test "em production, ALLOWED_EMAILS ausente nega qualquer email (fail-closed)" do
    with_env("ALLOWED_EMAILS" => nil) do
      with_rails_env("production") do
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google_oauth2",
          uid: "google-prod-noenv",
          info: { email: "anyone@anywhere.com", name: "Anyone", image: nil }
        )

        assert_no_difference "User.count" do
          get "/api/v1/auth/google_oauth2/callback"
        end
        assert_match "unauthorized_email", response.location
      end
    end
  end

  test "allowlist normaliza maiúsculas e espaços (email do Google chega como vier)" do
    with_allowed_emails(" Kaleb@Ferreri.co , wife@example.com ") do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "google-case",
        info: { email: "KALEB@ferreri.CO", name: "Kaleb", image: nil }
      )

      assert_difference "User.count", 1 do
        get "/api/v1/auth/google_oauth2/callback"
      end
    end
  end

  private

  def with_allowed_emails(emails_str, &block)
    with_env("ALLOWED_EMAILS" => emails_str, &block)
  end

  def with_env(vars)
    saved = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # Troca Rails.env só dentro do bloco (só afeta código que CONSULTA o env,
  # como email_allowed? — não reconfigura middleware/inicializadores).
  def with_rails_env(name)
    original = Rails.env
    Rails.env = name
    yield
  ensure
    Rails.env = original
  end

  # ---- /sessions/current -----------------------------------------------

  test "GET /sessions/current returns 401 when not signed in" do
    get "/api/v1/sessions/current"
    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "unauthenticated", body.dig("error", "code")
  end

  test "GET /sessions/current returns user info when signed in" do
    user = create(:user, email: "kaleb@example.com", name: "Kaleb")
    sign_in_as(user)

    get "/api/v1/sessions/current"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal user.id,             body.dig("user", "id")
    assert_equal "kaleb@example.com", body.dig("user", "email")
    assert_equal "Kaleb",             body.dig("user", "name")
  end

  # ---- DELETE /sessions/current ----------------------------------------

  test "DELETE /sessions/current logs the user out" do
    user = create(:user)
    sign_in_as(user)

    delete "/api/v1/sessions/current"
    assert_response :no_content

    get "/api/v1/sessions/current"
    assert_response :unauthorized
  end

  # ---- test_sign_in (E2E bypass) ---------------------------------------

  test "POST /auth/test_sign_in creates and signs in a user" do
    assert_difference "User.count", 1 do
      post "/api/v1/auth/test_sign_in", params: { email: "test@example.com", name: "Tester" }, as: :json
    end
    assert_response :no_content

    get "/api/v1/sessions/current"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "test@example.com", body.dig("user", "email")
    assert_equal "Tester",           body.dig("user", "name")
  end

  test "POST /auth/test_sign_in is idempotent (same email logs the same user)" do
    post "/api/v1/auth/test_sign_in", params: { email: "kaleb@example.com" }, as: :json
    get "/api/v1/sessions/current"
    first_id = JSON.parse(response.body).dig("user", "id")

    delete "/api/v1/sessions/current"

    assert_no_difference "User.count" do
      post "/api/v1/auth/test_sign_in", params: { email: "kaleb@example.com" }, as: :json
    end
    get "/api/v1/sessions/current"
    assert_equal first_id, JSON.parse(response.body).dig("user", "id")
  end
end
