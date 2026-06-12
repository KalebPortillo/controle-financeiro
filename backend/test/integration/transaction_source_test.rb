require "test_helper"

# RF2.7 — "exibir mais detalhes": payload cru do Pluggy (source_metadata) de uma
# transação, lazy (fora da listagem).
class TransactionSourceTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
    @account    = create(:account, workspace: @workspace, owner_membership: @membership)
  end

  test "GET /transactions/:id/source devolve o source_metadata" do
    raw = { "id" => "pluggy-1", "amount" => -50, "merchant" => { "businessName" => "VIVO S.A." } }
    t = create(:transaction, workspace: @workspace, account: @account,
                             source: "automatic_sync", source_metadata: raw)

    get "/api/v1/transactions/#{t.id}/source"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "automatic_sync", body["source"]
    assert_equal "VIVO S.A.", body.dig("source_metadata", "merchant", "businessName")
  end

  test "transação de outro workspace → 404" do
    other  = create(:workspace)
    alheia = create(:transaction, workspace: other, account: create(:account, workspace: other))
    get "/api/v1/transactions/#{alheia.id}/source"
    assert_response :not_found
  end

  test "exige auth" do
    t = create(:transaction, workspace: @workspace, account: @account)
    delete "/api/v1/sessions/current"
    get "/api/v1/transactions/#{t.id}/source"
    assert_response :unauthorized
  end
end
