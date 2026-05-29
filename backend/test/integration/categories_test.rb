require "test_helper"

# RF6 — categorias: gestão (CRUD + tags + merge), escopada por workspace.
class CategoriesTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
  end

  test "GET /categories lista com tags, escopado no workspace" do
    cat = create(:category, workspace: @workspace, name: "Alimentação")
    tag = create(:tag, workspace: @workspace, name: "Padaria")
    cat.tags << tag
    create(:category, workspace: create(:workspace), name: "Outra")

    get "/api/v1/categories"
    assert_response :ok
    cats = JSON.parse(response.body)["categories"]
    assert_equal 1, cats.size
    c = cats.first
    assert_equal "Alimentação", c["name"]
    assert_equal [ tag.id ], c["tags"].map { |t| t["id"] }
  end

  test "GET /categories exige auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/categories"
    assert_response :unauthorized
  end

  test "POST /categories cria com tags" do
    t1 = create(:tag, workspace: @workspace, name: "A")
    t2 = create(:tag, workspace: @workspace, name: "B")
    assert_difference -> { @workspace.categories.count }, 1 do
      post "/api/v1/categories",
           params: { name: "Casa", color: "#7C3AED", tag_ids: [ t1.id, t2.id ] }, as: :json
    end
    assert_response :created
    cat = @workspace.categories.find_by(name: "Casa")
    assert_equal [ t1.id, t2.id ].sort, cat.tags.pluck(:id).sort
  end

  test "POST /categories nome duplicado → 422" do
    create(:category, workspace: @workspace, name: "Casa")
    post "/api/v1/categories", params: { name: "casa" }, as: :json
    assert_response :unprocessable_entity
  end

  test "PATCH /categories/:id renomeia e substitui tags" do
    cat = create(:category, workspace: @workspace, name: "Casa")
    old = create(:tag, workspace: @workspace, name: "Old")
    nw  = create(:tag, workspace: @workspace, name: "New")
    cat.tags << old

    patch "/api/v1/categories/#{cat.id}",
          params: { name: "Lar", tag_ids: [ nw.id ] }, as: :json
    assert_response :ok
    cat.reload
    assert_equal "Lar", cat.name
    assert_equal [ nw.id ], cat.tags.pluck(:id)
  end

  test "PATCH ignora tag de outro workspace" do
    cat = create(:category, workspace: @workspace, name: "Casa")
    foreign = create(:tag, workspace: create(:workspace), name: "Alheia")
    patch "/api/v1/categories/#{cat.id}", params: { tag_ids: [ foreign.id ] }, as: :json
    assert_response :ok
    assert_empty cat.reload.tags
  end

  test "DELETE /categories/:id remove" do
    cat = create(:category, workspace: @workspace, name: "Casa")
    assert_difference -> { Category.count }, -1 do
      delete "/api/v1/categories/#{cat.id}"
    end
    assert_response :no_content
  end

  test "DELETE de outro workspace → 404" do
    foreign = create(:category, workspace: create(:workspace), name: "X")
    delete "/api/v1/categories/#{foreign.id}"
    assert_response :not_found
    assert Category.exists?(foreign.id)
  end

  test "POST /categories/:id/merge move tags pro destino e apaga origem" do
    src  = create(:category, workspace: @workspace, name: "Comida")
    dest = create(:category, workspace: @workspace, name: "Alimentação")
    t1 = create(:tag, workspace: @workspace, name: "Padaria")
    t2 = create(:tag, workspace: @workspace, name: "Mercado")
    src.tags << [ t1, t2 ]
    dest.tags << t2 # já existe no destino → não duplica

    post "/api/v1/categories/#{src.id}/merge", params: { into_category_id: dest.id }, as: :json
    assert_response :ok
    assert_not Category.exists?(src.id)
    assert_equal [ t1.id, t2.id ].sort, dest.reload.tags.pluck(:id).sort
  end
end
