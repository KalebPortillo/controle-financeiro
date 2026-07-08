require "test_helper"

class BudgetsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, email: "b-#{SecureRandom.hex(4)}@example.com", google_uid: SecureRandom.hex(6))
    sign_in_as(@user)
    @ws  = @user.workspace_memberships.first.workspace
    @acc = create(:account, workspace: @ws)
    @tag = create(:tag, workspace: @ws)
  end

  test "creates a tag budget and lists it with progress" do
    post "/api/v1/budgets", params: {
      name: "Mercado", kind: "tag", target_tag_id: @tag.id, monthly_limit_cents: 80_000
    }
    assert_response :created
    id = JSON.parse(response.body).dig("budget", "id")
    assert id.present?

    # um gasto consolidado com a tag, no mês corrente
    t = create(:transaction, workspace: @ws, account: @acc, direction: "debit",
               amount_cents: 20_000, status: "consolidated", occurred_at: Date.current)
    t.tags = [ @tag ]

    get "/api/v1/budgets"
    assert_response :success
    b = JSON.parse(response.body)["budgets"].find { |x| x["id"] == id }
    assert_equal 20_000, b.dig("progress", "spent_cents")
    assert_equal 25,     b.dig("progress", "pct")
    assert_equal "ok",   b.dig("progress", "status")
  end

  test "creates a composite budget with tags" do
    t2 = create(:tag, workspace: @ws)
    post "/api/v1/budgets", params: {
      name: "Lazer", kind: "composite", composite_tag_ids: [ @tag.id, t2.id ], monthly_limit_cents: 50_000
    }
    assert_response :created
    body = JSON.parse(response.body)["budget"]
    assert_equal 2, body["composite_tags"].size
  end

  test "rejects invalid budget (limit <= 0)" do
    post "/api/v1/budgets", params: { name: "X", kind: "tag", target_tag_id: @tag.id, monthly_limit_cents: 0 }
    assert_response :unprocessable_entity
  end

  test "updates and deletes a budget" do
    budget = create(:budget, workspace: @ws, target_tag: @tag, monthly_limit_cents: 80_000)
    patch "/api/v1/budgets/#{budget.id}", params: { monthly_limit_cents: 120_000 }
    assert_response :success
    assert_equal 120_000, budget.reload.monthly_limit_cents

    delete "/api/v1/budgets/#{budget.id}"
    assert_response :no_content
    assert_not Budget.exists?(budget.id)
  end

  test "does not touch budgets from another workspace" do
    other = create(:budget, workspace: create(:workspace))
    patch "/api/v1/budgets/#{other.id}", params: { monthly_limit_cents: 1 }
    assert_response :not_found
  end

  test "show returns progress, multi-month history and composing transactions" do
    budget = create(:budget, workspace: @ws, target_tag: @tag, monthly_limit_cents: 80_000)
    t = create(:transaction, workspace: @ws, account: @acc, direction: "debit",
               amount_cents: 30_000, status: "consolidated", occurred_at: Date.current, improved_title: "Feira")
    t.tags = [ @tag ]

    get "/api/v1/budgets/#{budget.id}"
    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 30_000, body.dig("budget", "progress", "spent_cents")
    assert_equal 6, body["history"].size
    assert_equal body["history"].last["month"], Date.current.strftime("%Y-%m")
    titles = body["transactions"].map { |x| x["title"] }
    assert_includes titles, "Feira"
  end

  test "flags overlap between budgets sharing a tag" do
    cat = create(:category, workspace: @ws, tags: [ @tag ])
    create(:budget, workspace: @ws, target_tag: @tag, name: "por tag")
    create(:budget, :category, workspace: @ws, target_category: cat, name: "por categoria")

    get "/api/v1/budgets"
    budgets = JSON.parse(response.body)["budgets"]
    assert budgets.all? { |b| b["overlap"] }, "ambos deveriam sinalizar overlap"
  end
end
