require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    # Cada teste começa com cache limpo pra não vazar contagem entre runs.
    Rack::Attack.cache.store.clear
    @original_enabled = Rack::Attack.enabled
    Rack::Attack.enabled = true
  end

  teardown do
    Rack::Attack.enabled = @original_enabled
  end

  test "throttles bursts on /api/v1/auth/* per IP" do
    limit = 10
    headers = { "REMOTE_ADDR" => "203.0.113.10" }

    # Até o limite, o middleware deixa passar (mesmo que o status final
    # seja redirect/302 do OmniAuth — o que importa é não vir 429).
    limit.times do |i|
      get "/api/v1/auth/google_oauth2/callback", env: headers
      assert_not_equal 429, response.status, "request #{i + 1} should not be throttled"
    end

    # A próxima volta tem que ser 429.
    get "/api/v1/auth/google_oauth2/callback", env: headers
    assert_response :too_many_requests
  end

  test "throttle on /auth/* is per-IP (outras IPs não são afetadas)" do
    limit = 10
    limit.times do
      get "/api/v1/auth/google_oauth2/callback", env: { "REMOTE_ADDR" => "203.0.113.10" }
    end

    # Quando o burst do IP A passou do teto, IP B ainda passa normalmente.
    get "/api/v1/auth/google_oauth2/callback", env: { "REMOTE_ADDR" => "203.0.113.10" }
    assert_response :too_many_requests

    get "/api/v1/auth/google_oauth2/callback", env: { "REMOTE_ADDR" => "203.0.113.11" }
    assert_not_equal 429, response.status
  end

  test "/up healthcheck is never throttled" do
    100.times do
      get "/up", env: { "REMOTE_ADDR" => "203.0.113.99" }
      assert_not_equal 429, response.status
    end
  end

  test "throttle response body is JSON with code 'rate_limited'" do
    headers = { "REMOTE_ADDR" => "203.0.113.20" }
    11.times { get "/api/v1/auth/google_oauth2/callback", env: headers }
    assert_response :too_many_requests
    body = JSON.parse(response.body)
    assert_equal "rate_limited", body.dig("error", "code")
  end
end
