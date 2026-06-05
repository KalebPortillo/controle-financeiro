require "test_helper"

# Erro de IA classificado (camada de feedback). Cada erro carrega um `reason`
# (categoria), uma `user_message` PT-BR amigável e se é `retryable?`.
class AiProviders::ApiErrorTest < ActiveSupport::TestCase
  test "defaults to a generic, retryable error" do
    err = AiProviders::ApiError.new("boom")
    assert_equal :error, err.reason
    assert err.retryable?
    assert err.user_message.present?
    assert_equal "boom", err.message
  end

  test "quota is permanent (not retryable) with a friendly message" do
    err = AiProviders::ApiError.new("HTTP 429 depleted", reason: :quota)
    assert_equal :quota, err.reason
    refute err.retryable?
    assert_match(/limite/i, err.user_message)
  end

  test "rate_limit and unavailable are retryable" do
    assert AiProviders::ApiError.new("x", reason: :rate_limit).retryable?
    assert AiProviders::ApiError.new("x", reason: :unavailable).retryable?
  end

  test "unknown reason falls back to :error" do
    assert_equal :error, AiProviders::ApiError.new("x", reason: :nonsense).reason
  end

  test "to_h exposes reason + friendly message for the channel" do
    err = AiProviders::ApiError.new("Gemini HTTP 503: down", reason: :unavailable)
    h = err.to_h
    assert_equal "unavailable", h[:reason]
    assert_equal err.user_message, h[:message]
    assert_equal "Gemini HTTP 503: down", h[:detail]
  end
end
