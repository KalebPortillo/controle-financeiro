require "test_helper"

# RF5 — tags: CRUD básico (list/autocomplete/create) + aplicação em transações.
class TagsTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
  end

  # --- index / autocomplete ---------------------------------------------

  test "GET /tags lista as tags do workspace com usage_count, escopado" do
    mercado = create(:tag, workspace: @workspace, name: "Mercado")
    create(:tag, workspace: @workspace, name: "Lazer")
    create(:tag, workspace: create(:workspace), name: "Outro") # outro workspace

    account = create(:account, workspace: @workspace, owner_membership: @membership)
    t = create(:transaction, workspace: @workspace, account: account)
    t.tags << mercado

    get "/api/v1/tags"
    assert_response :ok
    tags = JSON.parse(response.body)["tags"]
    assert_equal 2, tags.size
    m = tags.find { |x| x["name"] == "Mercado" }
    assert_equal 1, m["usage_count"]
  end

  test "GET /tags?q= filtra por prefixo (autocomplete, case-insensitive)" do
    create(:tag, workspace: @workspace, name: "Mercado")
    create(:tag, workspace: @workspace, name: "Mecânico")
    create(:tag, workspace: @workspace, name: "Lazer")

    get "/api/v1/tags?q=me"
    names = JSON.parse(response.body)["tags"].map { |t| t["name"] }.sort
    assert_equal [ "Mecânico", "Mercado" ], names
  end

  test "GET /tags exige auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/tags"
    assert_response :unauthorized
  end

  # --- create -----------------------------------------------------------

  test "POST /tags cria uma tag no workspace" do
    assert_difference -> { @workspace.tags.count }, 1 do
      post "/api/v1/tags", params: { name: "Mercado", color: "#34d399" }, as: :json
    end
    assert_response :created
    body = JSON.parse(response.body).fetch("tag")
    assert_equal "Mercado", body["name"]
    assert_equal "#34d399", body["color"]
  end

  test "POST /tags com nome duplicado → 422" do
    create(:tag, workspace: @workspace, name: "Mercado")
    post "/api/v1/tags", params: { name: "mercado" }, as: :json
    assert_response :unprocessable_entity
  end

  test "POST /tags sem nome → 422" do
    post "/api/v1/tags", params: { name: "" }, as: :json
    assert_response :unprocessable_entity
  end

  # --- update -----------------------------------------------------------

  test "PATCH /tags/:id edita nome e cor" do
    tag = create(:tag, workspace: @workspace, name: "Mercado")
    patch "/api/v1/tags/#{tag.id}", params: { name: "Supermercado", color: "#f00" }, as: :json
    assert_response :ok
    tag.reload
    assert_equal "Supermercado", tag.name
    assert_equal "#f00", tag.color
  end

  test "PATCH /tags/:id com nome duplicado → 422" do
    create(:tag, workspace: @workspace, name: "Lazer")
    tag = create(:tag, workspace: @workspace, name: "Mercado")
    patch "/api/v1/tags/#{tag.id}", params: { name: "lazer" }, as: :json
    assert_response :unprocessable_entity
  end

  test "PATCH /tags de outro workspace → 404" do
    foreign = create(:tag, workspace: create(:workspace), name: "Alheia")
    patch "/api/v1/tags/#{foreign.id}", params: { name: "X" }, as: :json
    assert_response :not_found
  end

  # --- delete -----------------------------------------------------------

  test "DELETE /tags/:id remove tag não usada" do
    tag = create(:tag, workspace: @workspace, name: "Sem uso")
    assert_difference -> { Tag.count }, -1 do
      delete "/api/v1/tags/#{tag.id}"
    end
    assert_response :no_content
  end

  test "DELETE /tags/:id em uso → 422 orientando merge" do
    tag = create(:tag, workspace: @workspace, name: "Em uso")
    account = create(:account, workspace: @workspace, owner_membership: @membership)
    create(:transaction, workspace: @workspace, account: account).tags << tag

    assert_no_difference -> { Tag.count } do
      delete "/api/v1/tags/#{tag.id}"
    end
    assert_response :unprocessable_entity
    assert_equal "tag_in_use", JSON.parse(response.body).dig("error", "code")
  end

  # --- merge ------------------------------------------------------------

  test "POST /tags/:id/merge move relações pro destino e apaga origem" do
    account = create(:account, workspace: @workspace, owner_membership: @membership)
    src  = create(:tag, workspace: @workspace, name: "Comida")
    dest = create(:tag, workspace: @workspace, name: "Alimentação")
    t1 = create(:transaction, workspace: @workspace, account: account)
    t2 = create(:transaction, workspace: @workspace, account: account)
    t1.tags << src
    t2.tags << [ src, dest ] # t2 já tem dest → não pode duplicar no merge

    post "/api/v1/tags/#{src.id}/merge", params: { into_tag_id: dest.id }, as: :json
    assert_response :ok

    assert_not Tag.exists?(src.id)
    assert_includes t1.reload.tags, dest
    assert_equal [ dest.id ], t2.reload.tags.pluck(:id) # sem duplicar
  end

  test "merge com destino de outro workspace → 404" do
    src = create(:tag, workspace: @workspace, name: "Comida")
    foreign = create(:tag, workspace: create(:workspace), name: "Alheia")
    post "/api/v1/tags/#{src.id}/merge", params: { into_tag_id: foreign.id }, as: :json
    assert_response :not_found
    assert Tag.exists?(src.id)
  end

  # --- aplicar na transação (inbox) -------------------------------------

  test "PATCH /transactions/:id com tag_ids substitui as tags" do
    account = create(:account, workspace: @workspace, owner_membership: @membership)
    t = create(:transaction, workspace: @workspace, account: account, status: "pending")
    a = create(:tag, workspace: @workspace, name: "A")
    b = create(:tag, workspace: @workspace, name: "B")
    t.tags << a

    patch "/api/v1/transactions/#{t.id}",
          params: { lock_version: t.lock_version, tag_ids: [ b.id ] }, as: :json
    assert_response :ok
    assert_equal [ b.id ], t.reload.tags.pluck(:id)

    returned = JSON.parse(response.body).dig("transaction", "tags").map { |x| x["id"] }
    assert_equal [ b.id ], returned
  end

  test "PATCH com tag_ids vazio limpa as tags" do
    account = create(:account, workspace: @workspace, owner_membership: @membership)
    t = create(:transaction, workspace: @workspace, account: account)
    t.tags << create(:tag, workspace: @workspace, name: "A")

    patch "/api/v1/transactions/#{t.id}",
          params: { lock_version: t.lock_version, tag_ids: [] }, as: :json
    assert_response :ok
    assert_empty t.reload.tags
  end

  test "PATCH ignora tag_id de outro workspace (não aplica)" do
    account = create(:account, workspace: @workspace, owner_membership: @membership)
    t = create(:transaction, workspace: @workspace, account: account)
    foreign = create(:tag, workspace: create(:workspace), name: "Alheia")

    patch "/api/v1/transactions/#{t.id}",
          params: { lock_version: t.lock_version, tag_ids: [ foreign.id ] }, as: :json
    assert_response :ok
    assert_empty t.reload.tags
  end
end
