require "test_helper"

# RF12 — entrada manual: cria gasto/receita do zero, direto pra consolidados.
class TransactionsManualEntryTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
  end

  test "POST /transactions cria gasto manual consolidado na conta Dinheiro/Externo" do
    assert_difference -> { @workspace.transactions.count }, 1 do
      post "/api/v1/transactions",
           params: { direction: "debit", amount_cents: 4500, occurred_at: "2026-05-20", improved_title: "Feira" },
           as: :json
    end
    assert_response :created
    t = @workspace.transactions.order(:created_at).last
    assert_equal "consolidated", t.status
    assert_equal "manual_entry", t.source
    assert_equal "Feira", t.improved_title
    assert_equal 4500, t.amount_cents
    assert_not_nil t.consolidated_at
    assert_equal @membership.id, t.created_by_membership_id
    assert_equal "manual", t.account.institution
    assert_equal "Dinheiro / Externo", t.account.name
  end

  test "reusa a mesma conta manual em lançamentos subsequentes (não duplica)" do
    post "/api/v1/transactions", params: { direction: "debit", amount_cents: 100, occurred_at: "2026-05-20" }, as: :json
    post "/api/v1/transactions", params: { direction: "credit", amount_cents: 200, occurred_at: "2026-05-21" }, as: :json
    assert_equal 1, @workspace.accounts.where(institution: "manual").count
  end

  test "aplica tags no lançamento manual" do
    tag = create(:tag, workspace: @workspace, name: "Comida")
    post "/api/v1/transactions",
         params: { direction: "debit", amount_cents: 100, occurred_at: "2026-05-20", tag_ids: [ tag.id ] },
         as: :json
    assert_response :created
    t = @workspace.transactions.order(:created_at).last
    assert_equal [ tag.id ], t.tags.pluck(:id)
  end

  test "valor inválido → 422" do
    post "/api/v1/transactions",
         params: { direction: "debit", amount_cents: 0, occurred_at: "2026-05-20" }, as: :json
    assert_response :unprocessable_entity
  end

  test "direction faltando → 422" do
    post "/api/v1/transactions", params: { amount_cents: 100, occurred_at: "2026-05-20" }, as: :json
    assert_response :unprocessable_entity
  end

  test "exige auth" do
    delete "/api/v1/sessions/current"
    post "/api/v1/transactions", params: { direction: "debit", amount_cents: 100, occurred_at: "2026-05-20" }, as: :json
    assert_response :unauthorized
  end
end
