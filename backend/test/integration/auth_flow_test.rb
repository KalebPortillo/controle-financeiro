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
