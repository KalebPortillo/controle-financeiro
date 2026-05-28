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
