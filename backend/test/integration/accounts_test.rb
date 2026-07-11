require "test_helper"

class AccountsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
  end

  test "index lists workspace accounts with owner and kind" do
    checking = create(:account, workspace: @workspace, kind: "checking", name: "Conta Nubank")
    card     = create(:account, workspace: @workspace, kind: "credit_card", name: "Cartão Nubank")

    get "/api/v1/accounts"
    assert_response :ok
    body = JSON.parse(response.body)
    ids = body["accounts"].map { |a| a["id"] }
    assert_includes ids, checking.id
    assert_includes ids, card.id

    serialized = body["accounts"].find { |a| a["id"] == card.id }
    assert_equal "credit_card", serialized["kind"]
    assert_equal card.owner_membership_id, serialized["owner_membership_id"]
  end

  test "index is scoped to the current workspace" do
    other_ws_account = create(:account) # different workspace
    get "/api/v1/accounts"
    ids = JSON.parse(response.body)["accounts"].map { |a| a["id"] }
    assert_not_includes ids, other_ws_account.id
  end

  test "index requires authentication" do
    delete "/api/v1/sessions/current"
    get "/api/v1/accounts"
    assert_response :unauthorized
  end
end
