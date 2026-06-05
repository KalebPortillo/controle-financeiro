require "test_helper"

# Canal de erro de IA no workspace (camada de feedback). Guarda o último erro
# não-recuperável de IA pra UI mostrar (onboarding/inbox); limpa no próximo
# sucesso.
class WorkspaceAiErrorTest < ActiveSupport::TestCase
  setup { @workspace = create(:workspace) }

  test "starts with no ai error" do
    assert_nil @workspace.ai_last_error
    assert_nil @workspace.ai_error_payload
  end

  test "record_ai_error! persists reason + friendly message + timestamp" do
    err = AiProviders::ApiError.new("Gemini HTTP 429: depleted", reason: :quota)
    @workspace.record_ai_error!(err)

    payload = @workspace.reload.ai_error_payload
    assert_equal "quota", payload[:reason]
    assert_equal err.user_message, payload[:message]
    assert payload[:at].present?
  end

  test "clear_ai_error! wipes it" do
    @workspace.record_ai_error!(AiProviders::ApiError.new("x", reason: :unavailable))
    @workspace.clear_ai_error!
    assert_nil @workspace.reload.ai_last_error
    assert_nil @workspace.ai_error_payload
  end

  test "clear_ai_error! is a no-op when already clear (no needless write)" do
    assert_no_changes -> { @workspace.reload.updated_at } do
      @workspace.clear_ai_error!
    end
  end
end
