require "test_helper"

# RF17 — config do vínculo Telegram: status, gerar deep-link, desvincular.
class TelegramLinkTest < ActionDispatch::IntegrationTest
  setup do
    @user      = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
  end

  test "GET /telegram_link sem vínculo" do
    get "/api/v1/telegram_link"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal false, body["linked"]
    assert_nil body["chat_title"]
  end

  test "GET /telegram_link vinculado" do
    @workspace.update!(telegram_chat_id: -1, telegram_chat_title: "Casa",
                       telegram_linked_at: Time.current)

    get "/api/v1/telegram_link"
    body = JSON.parse(response.body)
    assert_equal true, body["linked"]
    assert_equal "Casa", body["chat_title"]
    assert body["linked_at"].present?
  end

  test "POST /telegram_link gera código e deep-link startgroup" do
    post "/api/v1/telegram_link"
    assert_response :ok
    body = JSON.parse(response.body)

    @workspace.reload
    assert @workspace.telegram_link_code.present?
    assert @workspace.telegram_link_code_expires_at > 10.minutes.from_now
    assert_equal "https://t.me/#{ENV.fetch('TELEGRAM_BOT_USERNAME')}" \
                 "?startgroup=#{@workspace.telegram_link_code}",
                 body["deep_link"]
    assert body["expires_at"].present?
  end

  test "POST repetido troca o código (invalida o anterior)" do
    post "/api/v1/telegram_link"
    first = @workspace.reload.telegram_link_code

    post "/api/v1/telegram_link"
    assert_not_equal first, @workspace.reload.telegram_link_code
  end

  test "DELETE /telegram_link desvincula tudo" do
    @workspace.update!(telegram_chat_id: -1, telegram_chat_title: "Casa",
                       telegram_linked_at: Time.current,
                       telegram_link_code: "x", telegram_link_code_expires_at: 1.hour.from_now)

    delete "/api/v1/telegram_link"
    assert_response :no_content

    @workspace.reload
    assert_nil @workspace.telegram_chat_id
    assert_nil @workspace.telegram_chat_title
    assert_nil @workspace.telegram_linked_at
    assert_nil @workspace.telegram_link_code
    assert_nil @workspace.telegram_link_code_expires_at
  end

  test "exige auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/telegram_link"
    assert_response :unauthorized
  end
end
