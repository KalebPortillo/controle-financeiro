require "test_helper"

# RF23 — transações relacionadas no serializer + desvincular.
class TransactionLinksTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
    @account    = create(:account, workspace: @workspace, owner_membership: @membership)
  end

  def txn(**attrs)
    create(:transaction, **{ workspace: @workspace, account: @account, status: "consolidated" }.merge(attrs))
  end

  def find_tx(id)
    get "/api/v1/transactions", params: { status: "consolidated" }
    JSON.parse(response.body)["transactions"].find { |t| t["id"] == id }
  end

  test "a compra expõe o IOF como satélite; o IOF aponta a origem" do
    buy = txn(improved_title: "Compra US", amount_cents: 6527)
    iof = txn(original_description: "IOF de compra internacional", amount_cents: 228)
    create(:transaction_link, workspace_obj: @workspace, primary_transaction: buy,
           related_transaction: iof, relation_type: "iof")

    related_of_buy = find_tx(buy.id)["related"]
    assert_equal 1, related_of_buy.size
    assert_equal "iof",       related_of_buy.first["relation_type"]
    assert_equal "satellite", related_of_buy.first["role"]
    assert_equal iof.id,      related_of_buy.first["transaction_id"]

    related_of_iof = find_tx(iof.id)["related"]
    assert_equal "origin", related_of_iof.first["role"]
    assert_equal buy.id,   related_of_iof.first["transaction_id"]
  end

  test "related é nil quando não há vínculo" do
    t = txn
    assert_nil find_tx(t.id)["related"]
  end

  test "DELETE /transaction_links/:id desvincula" do
    link = create(:transaction_link, workspace_obj: @workspace,
                  primary_transaction: txn, related_transaction: txn, relation_type: "iof")

    delete "/api/v1/transaction_links/#{link.id}"
    assert_response :no_content
    assert_not TransactionLink.exists?(link.id)
  end

  test "não desvincula link de outro workspace" do
    other = create(:workspace)
    other_acc = create(:account, workspace: other)
    link = create(:transaction_link, workspace_obj: other,
                  primary_transaction: create(:transaction, workspace: other, account: other_acc),
                  related_transaction: create(:transaction, workspace: other, account: other_acc))

    delete "/api/v1/transaction_links/#{link.id}"
    assert_response :not_found
    assert TransactionLink.exists?(link.id), "link de outro workspace não é apagado"
  end

  # --- RF23 Fase 3: vínculo manual ------------------------------------------

  test "POST /transactions/:id/link vincula manualmente o satélite à origem" do
    origin    = txn(improved_title: "Assinatura", amount_cents: 5000)
    satellite = txn(original_description: "TARIFA", amount_cents: 120)

    post "/api/v1/transactions/#{satellite.id}/link",
         params: { origin_id: origin.id, relation_type: "fee" }
    assert_response :created

    link = satellite.reload.link_as_related
    assert_equal origin, link.primary_transaction
    assert_equal "fee",  link.relation_type
    assert_equal "manual", link.origin
    assert_equal @membership, link.confirmed_by_membership

    # o serializer do satélite passa a apontar a origem
    body = JSON.parse(response.body)["transaction"]
    assert_equal "origin", body["related"].first["role"]
    assert_equal origin.id, body["related"].first["transaction_id"]
  end

  test "POST link com origem já vinculada devolve 422" do
    origin1   = txn(amount_cents: 5000)
    origin2   = txn(amount_cents: 7000)
    satellite = txn(amount_cents: 120)
    post "/api/v1/transactions/#{satellite.id}/link", params: { origin_id: origin1.id, relation_type: "fee" }
    assert_response :created

    post "/api/v1/transactions/#{satellite.id}/link", params: { origin_id: origin2.id, relation_type: "fee" }
    assert_response :unprocessable_entity
    assert_equal "invalid_link", JSON.parse(response.body).dig("error", "code")
  end

  test "GET /transactions/:id/link_candidates lista origens da mesma conta" do
    satellite = txn(original_description: "TARIFA", amount_cents: 120)
    origin    = txn(improved_title: "Figma", amount_cents: 5000)
    other_acc = create(:account, workspace: @workspace)
    _other    = txn(account: other_acc, amount_cents: 9000)

    get "/api/v1/transactions/#{satellite.id}/link_candidates"
    assert_response :success
    ids = JSON.parse(response.body)["link_candidates"].map { |t| t["id"] }
    assert_includes ids, origin.id
    assert_not_includes ids, satellite.id
    assert_not_includes ids, _other.id
  end

  test "link_candidates de outro workspace não vaza" do
    satellite = txn(amount_cents: 120)
    other = create(:workspace)
    other_acc = create(:account, workspace: other)
    foreign = create(:transaction, workspace: other, account: other_acc, amount_cents: 5000)

    get "/api/v1/transactions/#{satellite.id}/link_candidates", params: { q: "" }
    ids = JSON.parse(response.body)["link_candidates"].map { |t| t["id"] }
    assert_not_includes ids, foreign.id
  end
end
