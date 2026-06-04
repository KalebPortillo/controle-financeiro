require "test_helper"

# RF22 — catálogo de categorias sugeridas pela IA (2ª análise): listar, aceitar
# (cria Category + associa tags), recusar. Escopado por workspace.
class SuggestedCategoriesTest < ActionDispatch::IntegrationTest
  setup do
    @user      = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
  end

  test "GET /suggested_categories lists pending, scoped to workspace" do
    create(:suggested_category, workspace: @workspace, name: "Essenciais")
    create(:suggested_category, workspace: @workspace, name: "Aceita", status: "accepted")
    create(:suggested_category, workspace: create(:workspace), name: "Alheia")

    get "/api/v1/suggested_categories"
    assert_response :ok
    names = JSON.parse(response.body)["suggested_categories"].map { |s| s["name"] }
    assert_equal [ "Essenciais" ], names
  end

  test "GET /suggested_categories requires auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/suggested_categories"
    assert_response :unauthorized
  end

  test "POST accept creates the category and links its tags by name" do
    create(:tag, workspace: @workspace, name: "Alimentação")
    create(:tag, workspace: @workspace, name: "Transporte")
    suggestion = create(:suggested_category, workspace: @workspace, name: "Essenciais",
                        tag_names: [ "Alimentação", "Transporte" ])

    assert_difference -> { @workspace.categories.count }, 1 do
      post "/api/v1/suggested_categories/#{suggestion.id}/accept"
    end
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "Essenciais", body["category"]["name"]
    assert_equal [ "Alimentação", "Transporte" ], body["category"]["tags"].map { |t| t["name"] }
    assert_equal "accepted", suggestion.reload.status
  end

  test "accept reuses an existing category of the same name" do
    create(:category, workspace: @workspace, name: "Essenciais")
    suggestion = create(:suggested_category, workspace: @workspace, name: "Essenciais", tag_names: [])

    assert_no_difference -> { @workspace.categories.count } do
      post "/api/v1/suggested_categories/#{suggestion.id}/accept"
    end
    assert_response :ok
  end

  test "accept of another workspace's suggestion → 404" do
    foreign = create(:suggested_category, workspace: create(:workspace))
    post "/api/v1/suggested_categories/#{foreign.id}/accept"
    assert_response :not_found
  end

  test "DELETE dismisses the suggestion" do
    suggestion = create(:suggested_category, workspace: @workspace, name: "Recusada")
    delete "/api/v1/suggested_categories/#{suggestion.id}"
    assert_response :no_content
    assert_equal "dismissed", suggestion.reload.status
  end

  test "DELETE of another workspace's suggestion → 404" do
    foreign = create(:suggested_category, workspace: create(:workspace))
    delete "/api/v1/suggested_categories/#{foreign.id}"
    assert_response :not_found
  end
end
