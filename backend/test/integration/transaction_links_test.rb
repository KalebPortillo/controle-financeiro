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
end
