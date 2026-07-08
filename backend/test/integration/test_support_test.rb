require "test_helper"

# Endpoint de seed do E2E — só dev/test. Guarda o contrato que o Playwright usa
# (ids devolvidos) e o cenário criado.
class TestSupportTest < ActionDispatch::IntegrationTest
  setup do
    # Email/uid aleatórios (não a sequence do factory): workers paralelos são
    # forkados e herdam o mesmo contador de sequence → colidiriam no email.
    @user = create(:user, email: "seed-#{SecureRandom.hex(6)}@example.com",
                          google_uid: SecureRandom.hex(8))
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
  end

  test "related_inbox cria compra + IOF pendentes e vinculados" do
    post "/api/v1/test_support/seed", params: { scenario: "related_inbox" }
    assert_response :success
    body = JSON.parse(response.body)

    purchase = @workspace.transactions.find(body["purchase_id"])
    iof      = @workspace.transactions.find(body["iof_id"])
    assert_equal "pending", purchase.status
    assert_equal "pending", iof.status
    assert purchase.foreign?, "compra deve ser em moeda estrangeira"
    link = iof.link_as_related
    assert_equal purchase, link.primary_transaction
    assert_equal "iof", link.relation_type
  end

  test "link_manual cria dois consolidados sem vínculo na mesma conta" do
    post "/api/v1/test_support/seed", params: { scenario: "link_manual" }
    assert_response :success
    body = JSON.parse(response.body)

    origin = @workspace.transactions.find(body["origin_id"])
    orphan = @workspace.transactions.find(body["orphan_id"])
    assert_equal "consolidated", origin.status
    assert_equal "consolidated", orphan.status
    assert_equal origin.account_id, orphan.account_id
    assert_nil orphan.link_as_related
  end

  test "cenário desconhecido devolve 422" do
    post "/api/v1/test_support/seed", params: { scenario: "nope" }
    assert_response :unprocessable_entity
  end
end
