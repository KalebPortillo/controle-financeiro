require "test_helper"

# RF2.3 — ações da inbox: aceitar (consolidate), rejeitar, editar (com optimistic
# lock) e remover. Escopadas por workspace.
class TransactionsWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
    @account    = create(:account, workspace: @workspace, owner_membership: @membership)
  end

  def txn(**attrs)
    create(:transaction, **{ workspace: @workspace, account: @account, status: "pending" }.merge(attrs))
  end

  # --- consolidate ------------------------------------------------------

  test "consolidate move pending → consolidated e seta consolidated_at" do
    t = txn
    post "/api/v1/transactions/#{t.id}/consolidate"
    assert_response :ok
    t.reload
    assert_equal "consolidated", t.status
    assert_not_nil t.consolidated_at
    assert_equal "consolidated", JSON.parse(response.body).dig("transaction", "status")
  end

  # --- reject -----------------------------------------------------------

  test "reject move pending → rejected e seta rejected_at" do
    t = txn
    post "/api/v1/transactions/#{t.id}/reject"
    assert_response :ok
    t.reload
    assert_equal "rejected", t.status
    assert_not_nil t.rejected_at
  end

  # --- update (optimistic lock) -----------------------------------------

  test "update edita título/valor/data com lock_version correto" do
    t = txn(amount_cents: 1000)
    patch "/api/v1/transactions/#{t.id}",
          params: { lock_version: t.lock_version, improved_title: "Almoço", amount_cents: 2500 },
          as: :json
    assert_response :ok
    t.reload
    assert_equal "Almoço", t.improved_title
    assert_equal 2500, t.amount_cents
    assert_equal 1, t.lock_version
  end

  test "update com lock_version defasado → 409 conflict" do
    t = txn
    stale = t.lock_version
    # alguém edita antes (lock_version vira 1)
    t.update!(improved_title: "primeiro")

    patch "/api/v1/transactions/#{t.id}",
          params: { lock_version: stale, improved_title: "segundo" },
          as: :json
    assert_response :conflict
    assert_equal "primeiro", t.reload.improved_title
  end

  test "update com valor inválido → 422" do
    t = txn
    patch "/api/v1/transactions/#{t.id}",
          params: { lock_version: t.lock_version, amount_cents: 0 },
          as: :json
    assert_response :unprocessable_entity
  end

  # --- destroy ----------------------------------------------------------

  test "destroy remove a transação" do
    t = txn
    assert_difference -> { Transaction.count }, -1 do
      delete "/api/v1/transactions/#{t.id}"
    end
    assert_response :no_content
  end

  # --- scoping ----------------------------------------------------------

  test "ação em transação de outro workspace → 404" do
    other = create(:workspace)
    foreign = create(:transaction, workspace: other, account: create(:account, workspace: other))
    post "/api/v1/transactions/#{foreign.id}/consolidate"
    assert_response :not_found
  end

  test "exige auth" do
    t = txn
    delete "/api/v1/sessions/current"
    post "/api/v1/transactions/#{t.id}/consolidate"
    assert_response :unauthorized
  end
end
