require "test_helper"

# RF3/RF22 — catálogo de tags sugeridas pela IA: listar, aceitar (vira tag real,
# opcionalmente aplicada a uma transação), recusar. Escopado por workspace.
class SuggestedTagsTest < ActionDispatch::IntegrationTest
  setup do
    @user      = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
    @account   = create(:account, workspace: @workspace)
  end

  test "GET /suggested_tags lists pending suggestions scoped to workspace" do
    create(:suggested_tag, workspace: @workspace, name: "Mercado", coverage: 8)
    create(:suggested_tag, workspace: @workspace, name: "Aceita", status: "accepted")
    create(:suggested_tag, workspace: create(:workspace), name: "Alheia")

    get "/api/v1/suggested_tags"
    assert_response :ok
    names = JSON.parse(response.body)["suggested_tags"].map { |s| s["name"] }
    assert_equal [ "Mercado" ], names
  end

  test "GET /suggested_tags requires auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/suggested_tags"
    assert_response :unauthorized
  end

  test "POST /suggested_tags/:id/accept creates a real tag and marks accepted" do
    suggestion = create(:suggested_tag, workspace: @workspace, name: "Mercado")

    assert_difference -> { @workspace.tags.count }, 1 do
      post "/api/v1/suggested_tags/#{suggestion.id}/accept"
    end
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "Mercado", body["tag"]["name"]
    assert_equal "accepted", suggestion.reload.status
    assert @workspace.tags.exists?(name: "Mercado")
  end

  test "accept with transaction_id applies the new tag to that transaction" do
    suggestion = create(:suggested_tag, workspace: @workspace, name: "Transporte")
    tx = create(:transaction, workspace: @workspace, account: @account, status: "pending")

    post "/api/v1/suggested_tags/#{suggestion.id}/accept", params: { transaction_id: tx.id }, as: :json
    assert_response :ok
    assert_equal [ "Transporte" ], tx.reload.tags.pluck(:name)
  end

  test "accept reuses an existing tag with the same name (no duplicate)" do
    create(:tag, workspace: @workspace, name: "Mercado")
    suggestion = create(:suggested_tag, workspace: @workspace, name: "Mercado")

    assert_no_difference -> { @workspace.tags.count } do
      post "/api/v1/suggested_tags/#{suggestion.id}/accept"
    end
    assert_response :ok
  end

  test "accept of another workspace's suggestion → 404" do
    foreign = create(:suggested_tag, workspace: create(:workspace))
    post "/api/v1/suggested_tags/#{foreign.id}/accept"
    assert_response :not_found
  end

  test "DELETE /suggested_tags/:id dismisses the suggestion" do
    suggestion = create(:suggested_tag, workspace: @workspace, name: "Recusada")

    delete "/api/v1/suggested_tags/#{suggestion.id}"
    assert_response :no_content
    assert_equal "dismissed", suggestion.reload.status
  end

  test "DELETE of another workspace's suggestion → 404" do
    foreign = create(:suggested_tag, workspace: create(:workspace))
    delete "/api/v1/suggested_tags/#{foreign.id}"
    assert_response :not_found
    assert_equal "pending", foreign.reload.status
  end
end
