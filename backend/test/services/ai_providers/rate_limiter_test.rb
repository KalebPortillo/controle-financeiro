require "test_helper"

# Throttle pra caber no RPM do free tier: espaça as chamadas ao Gemini por um
# intervalo mínimo. Como a fila ai_suggestion roda 1 thread/1 processo, um estado
# em memória (timestamp da última chamada) basta.
class AiProviders::RateLimiterTest < ActiveSupport::TestCase
  setup { AiProviders::RateLimiter.reset! }
  teardown { AiProviders::RateLimiter.reset! }

  def with_interval(seconds)
    prev = ENV["AI_MIN_REQUEST_INTERVAL"]
    ENV["AI_MIN_REQUEST_INTERVAL"] = seconds.to_s
    yield
  ensure
    ENV["AI_MIN_REQUEST_INTERVAL"] = prev
  end

  test "first call does not wait" do
    with_interval(6) do
      slept = []
      AiProviders::RateLimiter.throttle!(clock: -> { 100.0 }, sleeper: ->(s) { slept << s })
      assert_empty slept
    end
  end

  test "a call too soon after the previous waits the remaining interval" do
    with_interval(6) do
      slept = []
      AiProviders::RateLimiter.throttle!(clock: -> { 100.0 }, sleeper: ->(s) { slept << s })
      AiProviders::RateLimiter.throttle!(clock: -> { 102.0 }, sleeper: ->(s) { slept << s })
      assert_equal 1, slept.size
      assert_in_delta 4.0, slept.first, 0.001 # 6 - (102-100)
    end
  end

  test "a call after the interval has elapsed does not wait" do
    with_interval(6) do
      slept = []
      AiProviders::RateLimiter.throttle!(clock: -> { 100.0 }, sleeper: ->(s) { slept << s })
      AiProviders::RateLimiter.throttle!(clock: -> { 110.0 }, sleeper: ->(s) { slept << s })
      assert_empty slept
    end
  end

  test "interval <= 0 disables throttling" do
    with_interval(0) do
      slept = []
      AiProviders::RateLimiter.throttle!(clock: -> { 1.0 }, sleeper: ->(s) { slept << s })
      AiProviders::RateLimiter.throttle!(clock: -> { 1.0 }, sleeper: ->(s) { slept << s })
      assert_empty slept
    end
  end
end
