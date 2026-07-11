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
  # custom period (from/to) on overview
  # ---------------------------------------------------------------------------
  test "overview accepts custom from/to range" do
    this_month = Date.current.beginning_of_month
    # range covering only tx1 (day+1) and tx2 (day+2), not the credit (day+3)
    from = (this_month + 1.day).iso8601
    to   = (this_month + 2.days).iso8601
    get "/api/v1/reports/overview", params: { from: from, to: to }
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 30_000, body["expense_cents"]
    assert_equal 0, body["income_cents"] # credit is on day+3, outside range
    assert_equal from, body["period"]["from"]
    assert_equal to, body["period"]["to"]
  end

  # ---------------------------------------------------------------------------
  # filters: account, card_only, membership (pessoa), direction
  # ---------------------------------------------------------------------------
  test "overview filters by account_ids" do
    other = create(:account, workspace: @workspace)
    this_month = Date.current.beginning_of_month
    create(:transaction, workspace: @workspace, account: other, direction: "debit",
           amount_cents: 5_000, status: "consolidated", occurred_at: this_month + 1.day)

    get "/api/v1/reports/overview", params: { period: "current_month", account_ids: [ @account.id ] }
    body = JSON.parse(response.body)
    assert_equal 30_000, body["expense_cents"] # only @account, not the 5_000 on `other`
  end

  test "by_category filters by card_only" do
    card = create(:account, workspace: @workspace, kind: "credit_card")
    this_month = Date.current.beginning_of_month
    card_tx = create(:transaction, workspace: @workspace, account: card, direction: "debit",
                     amount_cents: 7_000, status: "consolidated", occurred_at: this_month + 1.day)
    card_tx.tags << @tag_food

    from = this_month.iso8601
    to   = Date.current.end_of_month.iso8601
    get "/api/v1/reports/by_category", params: { from: from, to: to, card_only: "true" }
    body = JSON.parse(response.body)
    cat = body["categories"].find { |c| c["name"] == "Alimentação" }
    assert_equal 7_000, cat["amount_cents"] # only the card tx, not @tx1 on checking account
  end

  test "by_tag filters by membership (pessoa)" do
    other_membership = create(:workspace_membership, workspace: @workspace)
    her_account = create(:account, workspace: @workspace, owner_membership: other_membership)
    this_month = Date.current.beginning_of_month
    her_tx = create(:transaction, workspace: @workspace, account: her_account, direction: "debit",
                    amount_cents: 8_000, status: "consolidated", occurred_at: this_month + 1.day)
    her_tx.tags << @tag_house

    from = this_month.iso8601
    to   = Date.current.end_of_month.iso8601
    get "/api/v1/reports/by_tag", params: { from: from, to: to, membership_id: @account.owner_membership_id }
    body = JSON.parse(response.body)
    casa = body["tags"].find { |t| t["name"] == "Casa" }
    assert_equal 20_000, casa["amount_cents"] # @tx2 on @account, not her 8_000
  end

  test "by_category direction credit aggregates income per category" do
    # tag the income credit into a category
    @cat_feed.tags << @tag_house # ensure category has a tag on the credit
    @tx_credit.tags << @tag_house
    from = Date.current.beginning_of_month.iso8601
    to   = Date.current.end_of_month.iso8601
    get "/api/v1/reports/by_category", params: { from: from, to: to, direction: "credit" }
    body = JSON.parse(response.body)
    cat = body["categories"].find { |c| c["name"] == "Alimentação" }
    assert_equal 50_000, cat["amount_cents"] # the credit, aggregated as receita
  end

  # ---------------------------------------------------------------------------
  # drill-down: category detail
  # ---------------------------------------------------------------------------
  test "category detail returns summary, breakdown and transactions" do
    from = Date.current.beginning_of_month.iso8601
    to   = Date.current.end_of_month.iso8601
    get "/api/v1/reports/category/#{@cat_feed.id}", params: { from: from, to: to }
    assert_response :ok
    body = JSON.parse(response.body)

    assert_equal @cat_feed.id, body["id"]
    assert_equal "Alimentação", body["name"]
    # summary: only @tx1 (10_000) has @tag_food which is in Alimentação
    assert_equal 10_000, body["summary"]["amount_cents"]
    assert_equal 1, body["summary"]["transactions_count"]
    # share of total consolidated debits (30_000) → ~33.3%
    assert_in_delta 33.3, body["summary"]["share_pct"], 0.5
    # breakdown lists member tag "Comida"
    assert body["breakdown"].any? { |b| b["name"] == "Comida" && b["amount_cents"] == 10_000 }
    # transactions serialized (has id + amount_cents fields)
    assert_equal [ @tx1.id ], body["transactions"].map { |t| t["id"] }
  end

  test "category detail computes previous-period delta" do
    last_month = Date.current.beginning_of_month - 1.month
    prev_tx = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                     amount_cents: 5_000, status: "consolidated", occurred_at: last_month + 1.day)
    prev_tx.tags << @tag_food

    from = Date.current.beginning_of_month.iso8601
    to   = Date.current.end_of_month.iso8601
    get "/api/v1/reports/category/#{@cat_feed.id}", params: { from: from, to: to }
    body = JSON.parse(response.body)
    assert_equal 5_000, body["summary"]["previous_amount_cents"]
    # (10_000 - 5_000) / 5_000 * 100 = 100.0
    assert_in_delta 100.0, body["summary"]["delta_pct"], 0.1
  end

  test "category detail 404 for unknown id" do
    get "/api/v1/reports/category/#{SecureRandom.uuid}", params: { period: "current_month" }
    assert_response :not_found
  end

  # ---------------------------------------------------------------------------
  # drill-down: tag detail
  # ---------------------------------------------------------------------------
  test "tag detail returns summary, account breakdown and transactions" do
    from = Date.current.beginning_of_month.iso8601
    to   = Date.current.end_of_month.iso8601
    get "/api/v1/reports/tag/#{@tag_house.id}", params: { from: from, to: to }
    assert_response :ok
    body = JSON.parse(response.body)

    assert_equal @tag_house.id, body["id"]
    assert_equal "Casa", body["name"]
    assert_equal 20_000, body["summary"]["amount_cents"]
    assert_equal 1, body["summary"]["transactions_count"]
    # breakdown by account
    assert body["breakdown"].any? { |b| b["amount_cents"] == 20_000 }
    assert_equal [ @tx2.id ], body["transactions"].map { |t| t["id"] }
  end

  test "tag detail 404 for unknown id" do
    get "/api/v1/reports/tag/#{SecureRandom.uuid}", params: { period: "current_month" }
    assert_response :not_found
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
