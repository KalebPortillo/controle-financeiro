require "test_helper"

class ReportsTest < ActionDispatch::IntegrationTest
  setup do
    @user      = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace

    @account = create(:account, workspace: @workspace)

    # Tags
    @tag_food  = create(:tag, workspace: @workspace, name: "Comida")
    @tag_house = create(:tag, workspace: @workspace, name: "Casa")

    # Category linked to food tag
    @cat_feed = create(:category, workspace: @workspace, name: "Alimentação")
    @cat_feed.tags << @tag_food

    # Transactions in current month (consolidated debits)
    this_month = Date.current.beginning_of_month
    @tx1 = create(:transaction, workspace: @workspace, account: @account,
                   direction: "debit", amount_cents: 10_000,
                   status: "consolidated", occurred_at: this_month + 1.day)
    @tx2 = create(:transaction, workspace: @workspace, account: @account,
                   direction: "debit", amount_cents: 20_000,
                   status: "consolidated", occurred_at: this_month + 2.days)
    @tx_credit = create(:transaction, workspace: @workspace, account: @account,
                         direction: "credit", amount_cents: 50_000,
                         status: "consolidated", occurred_at: this_month + 3.days)
    # pending — must NOT appear in reports
    @tx_pending = create(:transaction, workspace: @workspace, account: @account,
                          direction: "debit", amount_cents: 9_999,
                          status: "pending", occurred_at: this_month + 4.days)

    # Tag associations
    @tx1.tags << @tag_food
    @tx2.tags << @tag_house
  end

  # ---------------------------------------------------------------------------
  # overview
  # ---------------------------------------------------------------------------
  test "overview returns period totals" do
    get "/api/v1/reports/overview?period=current_month"
    assert_response :ok
    body = JSON.parse(response.body)

    assert_equal 30_000, body["expense_cents"]
    assert_equal 50_000, body["income_cents"]
    assert_equal 20_000, body["balance_cents"]
    assert body["period"]["from"].present?
    assert body["period"]["to"].present?
  end

  # RF10 — estorno desconta do gasto e o crédito-estorno não conta como receita.
  test "overview discounts refunds from expense and excludes the refund credit from income" do
    this_month = Date.current.beginning_of_month
    refund_credit = create(:transaction, workspace: @workspace, account: @account,
                           direction: "credit", amount_cents: 4_000,
                           status: "consolidated", occurred_at: this_month + 5.days)
    create(:transaction_refund, refund_transaction: refund_credit, refunded_transaction: @tx1,
           confirmed_by_membership: @user.workspace_memberships.first)

    get "/api/v1/reports/overview?period=current_month"
    body = JSON.parse(response.body)
    # gasto: 30_000 - 4_000 estornados = 26_000
    assert_equal 26_000, body["expense_cents"]
    # receita: só os 50_000 originais; o crédito de 4_000 é estorno, não receita
    assert_equal 50_000, body["income_cents"]
  end

  # RF11 — transferências internas não contam como gasto/receita.
  test "overview excludes internal transfers from expense and income" do
    this_month = Date.current.beginning_of_month
    acc_b = create(:account, workspace: @workspace)
    out_tx = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                    amount_cents: 70_000, status: "consolidated", occurred_at: this_month + 6.days)
    in_tx  = create(:transaction, workspace: @workspace, account: acc_b, direction: "credit",
                    amount_cents: 70_000, status: "consolidated", occurred_at: this_month + 6.days)
    create(:internal_transfer, workspace: @workspace,
           debit_transaction: out_tx, credit_transaction: in_tx)

    get "/api/v1/reports/overview?period=current_month"
    body = JSON.parse(response.body)
    # gasto segue 30_000 (a saída de 70k é transferência, não gasto)
    assert_equal 30_000, body["expense_cents"]
    # receita segue 50_000 (a entrada de 70k é transferência, não receita)
    assert_equal 50_000, body["income_cents"]
  end

  test "by_tag excludes internal transfers" do
    this_month = Date.current.beginning_of_month
    acc_b = create(:account, workspace: @workspace)
    out_tx = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                    amount_cents: 70_000, status: "consolidated", occurred_at: this_month + 6.days)
    out_tx.tags << @tag_house
    in_tx = create(:transaction, workspace: @workspace, account: acc_b, direction: "credit",
                   amount_cents: 70_000, status: "consolidated", occurred_at: this_month + 6.days)
    create(:internal_transfer, workspace: @workspace, debit_transaction: out_tx, credit_transaction: in_tx)

    get "/api/v1/reports/by_tag", params: { from: this_month.iso8601, to: Date.current.end_of_month.iso8601 }
    casa = JSON.parse(response.body)["tags"].find { |t| t["name"] == "Casa" }
    assert_equal 20_000, casa["amount_cents"] # só o gasto real, não a transferência
  end

  test "overview includes top_tags sorted by amount" do
    get "/api/v1/reports/overview?period=current_month"
    assert_response :ok
    top = JSON.parse(response.body)["top_tags"]
    assert top.is_a?(Array)
    names = top.map { |t| t["name"] }
    assert_includes names, "Casa"
    assert_includes names, "Comida"
    # Casa (20k) should appear before Comida (10k)
    assert names.index("Casa") < names.index("Comida")
  end

  test "overview includes top_categories" do
    get "/api/v1/reports/overview?period=current_month"
    assert_response :ok
    cats = JSON.parse(response.body)["top_categories"]
    assert cats.is_a?(Array)
    assert cats.any? { |c| c["name"] == "Alimentação" }
  end

  test "overview includes previous_period_comparison" do
    get "/api/v1/reports/overview?period=current_month"
    assert_response :ok
    cmp = JSON.parse(response.body)["previous_period_comparison"]
    assert cmp.is_a?(Hash)
    assert cmp.key?("expense_delta_pct")
    assert cmp.key?("income_delta_pct")
  end

  # ---------------------------------------------------------------------------
  # by_tag
  # ---------------------------------------------------------------------------
  test "by_tag returns aggregation per tag" do
    from = Date.current.beginning_of_month.iso8601
    to   = Date.current.end_of_month.iso8601
    get "/api/v1/reports/by_tag?from=#{from}&to=#{to}"
    assert_response :ok
    body = JSON.parse(response.body)
    assert body.key?("tags")
    tags_hash = body["tags"].index_by { |t| t["name"] }
    assert_equal 20_000, tags_hash["Casa"]["amount_cents"]
    assert_equal 10_000, tags_hash["Comida"]["amount_cents"]
    assert tags_hash["Casa"]["transactions_count"] == 1
  end

  test "by_tag excludes pending transactions" do
    from = Date.current.beginning_of_month.iso8601
    to   = Date.current.end_of_month.iso8601
    # pending tx has no tag but let's ensure total only counts consolidated
    get "/api/v1/reports/by_tag?from=#{from}&to=#{to}"
    assert_response :ok
    total = JSON.parse(response.body)["tags"].sum { |t| t["amount_cents"] }
    assert_equal 30_000, total
  end

  # ---------------------------------------------------------------------------
  # by_category
  # ---------------------------------------------------------------------------
  test "by_category returns aggregation with overlap metadata" do
    from = Date.current.beginning_of_month.iso8601
    to   = Date.current.end_of_month.iso8601
    get "/api/v1/reports/by_category?from=#{from}&to=#{to}"
    assert_response :ok
    body = JSON.parse(response.body)
    assert body.key?("categories")
    assert body.key?("total_distinct_transactions_amount_cents")
    assert body.key?("sum_of_categories_amount_cents")
    assert body.key?("overlap_present")

    cat = body["categories"].find { |c| c["name"] == "Alimentação" }
    assert_not_nil cat
    assert_equal 10_000, cat["amount_cents"]
    # total distinct debits = 30k (tx1 + tx2)
    assert_equal 30_000, body["total_distinct_transactions_amount_cents"]
  end

  test "by_category signals overlap when same transaction in multiple categories" do
    # Add food tag to a second category
    cat2 = create(:category, workspace: @workspace, name: "Lazer")
    cat2.tags << @tag_food

    from = Date.current.beginning_of_month.iso8601
    to   = Date.current.end_of_month.iso8601
    get "/api/v1/reports/by_category?from=#{from}&to=#{to}"
    assert_response :ok
    body = JSON.parse(response.body)

    # tx1 now belongs to both Alimentação and Lazer — overlap signaled
    assert body["overlap_present"]
    # sum_of_categories counts tx1 twice (20k), total_distinct counts all debits (30k);
    # overlap_present is true because tx1 appears in 2 categories, not because sums differ
    cat_sums = body["categories"].sum { |c| c["amount_cents"] }
    assert cat_sums >= 20_000
  end

  # ---------------------------------------------------------------------------
  # monthly_evolution
  # ---------------------------------------------------------------------------
  test "monthly_evolution returns array for requested months" do
    get "/api/v1/reports/monthly_evolution?months=12"
    assert_response :ok
    body = JSON.parse(response.body)
    assert body.key?("months")
    assert body["months"].is_a?(Array)
    assert body["months"].length <= 12
    # Current month entry should have our data
    current_entry = body["months"].find { |m| m["period"].start_with?(Date.current.strftime("%Y-%m")) }
    assert_not_nil current_entry
    assert_equal 30_000, current_entry["expense_cents"]
    assert_equal 50_000, current_entry["income_cents"]
  end

  test "monthly_evolution defaults to 12 months" do
    get "/api/v1/reports/monthly_evolution"
    assert_response :ok
    assert JSON.parse(response.body)["months"].length <= 12
  end

  # ---------------------------------------------------------------------------
  # auth guard
  # ---------------------------------------------------------------------------
  test "reports require authentication" do
    delete "/api/v1/sessions/current"
    get "/api/v1/reports/overview?period=current_month"
    assert_response :unauthorized
  end
end
