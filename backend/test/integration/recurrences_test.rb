require "test_helper"

# RF9.2 — recorrentes: CRUD manual, escopado por workspace.
class RecurrencesTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
    @account    = create(:account, workspace: @workspace)
  end

  test "GET /recurrences lista escopado no workspace" do
    create(:recurrence, workspace: @workspace, account: @account, descriptor_pattern: "Aluguel")
    create(:recurrence, workspace: create(:workspace))

    get "/api/v1/recurrences"
    assert_response :ok
    recs = JSON.parse(response.body)["recurrences"]
    assert_equal 1, recs.size
    assert_equal "Aluguel", recs.first["descriptor_pattern"]
  end

  test "GET /recurrences exige auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/recurrences"
    assert_response :unauthorized
  end

  test "GET /recurrences/:id/transactions lista os gastos consolidados casando o padrão" do
    rec = create(:recurrence, workspace: @workspace, account: @account, descriptor_pattern: "NETFLIX")
    t1 = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                status: "consolidated", original_description: "NETFLIX 4821",
                occurred_at: Date.new(2026, 5, 10), improved_title: "Netflix")
    _t2 = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                 status: "consolidated", original_description: "NETFLIX 9931", occurred_at: Date.new(2026, 6, 10))
    _other = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                    status: "consolidated", original_description: "SPOTIFY", occurred_at: Date.new(2026, 6, 1))
    _pending = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                      status: "pending", original_description: "NETFLIX 0001", occurred_at: Date.new(2026, 6, 20))

    get "/api/v1/recurrences/#{rec.id}/transactions"
    assert_response :ok
    txs = JSON.parse(response.body)["transactions"]
    assert_equal 2, txs.size
    assert_equal "2026-06-10", txs.first["occurred_at"], "mais recente primeiro"
    assert_equal t1.id, txs.last["id"]
    assert_equal "Netflix", txs.last["title"]
  end

  test "GET /recurrences/:id/transactions não vaza de outro workspace" do
    other = create(:workspace)
    rec = create(:recurrence, workspace: other, account: create(:account, workspace: other))
    get "/api/v1/recurrences/#{rec.id}/transactions"
    assert_response :not_found
  end

  test "POST /recurrences cria manual (source forçado para manual)" do
    assert_difference -> { @workspace.recurrences.count }, 1 do
      post "/api/v1/recurrences",
           params: {
             account_id: @account.id,
             descriptor_pattern: "Netflix",
             expected_amount_cents: 5990,
             cadence: "monthly",
             next_expected_at: "2026-06-10",
             source: "detected" # deve ser ignorado
           }, as: :json
    end
    assert_response :created
    rec = @workspace.recurrences.find_by(descriptor_pattern: "Netflix")
    assert_equal "manual", rec.source
    assert_equal "active", rec.status
    assert_equal 5990, rec.expected_amount_cents
  end

  # RF9.7 — marcar uma transação como recorrente (semeia do gasto).
  test "POST /recurrences com transaction_id semeia recorrência do gasto" do
    3.times do |i|
      create(:transaction, workspace: @workspace, account: @account, direction: "debit",
             status: "consolidated", consolidated_at: Time.current,
             original_description: "NETFLIX.COM #{i}", amount_cents: 5990,
             occurred_at: Date.new(2026, 1, 10) + (i * 30))
    end
    seed = @workspace.transactions.find_by(original_description: "NETFLIX.COM 0")

    assert_difference -> { @workspace.recurrences.count }, 1 do
      post "/api/v1/recurrences", params: { transaction_id: seed.id }, as: :json
    end
    assert_response :created
    rec = @workspace.recurrences.sole
    assert_equal "manual",       rec.source
    assert_equal "NETFLIX COM",  rec.descriptor_pattern
    assert_equal @account.id,    rec.account_id
    assert_equal "monthly",      rec.cadence
    assert_equal 5990,           rec.expected_amount_cents
  end

  test "POST /recurrences com transaction_id de gasto único cai em mensal" do
    seed = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                  status: "consolidated", consolidated_at: Time.current,
                  original_description: "ALUGUEL", amount_cents: 180000, occurred_at: Date.new(2026, 5, 5))

    post "/api/v1/recurrences", params: { transaction_id: seed.id }, as: :json
    assert_response :created
    rec = @workspace.recurrences.sole
    assert_equal "monthly", rec.cadence
    assert_equal 180000,    rec.expected_amount_cents
    assert_equal Date.new(2026, 6, 5), rec.next_expected_at
  end

  test "POST /recurrences com transaction_id é idempotente (não duplica)" do
    seed = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                  status: "consolidated", consolidated_at: Time.current,
                  original_description: "SPOTIFY", amount_cents: 1990, occurred_at: Date.new(2026, 5, 5))
    post "/api/v1/recurrences", params: { transaction_id: seed.id }, as: :json
    assert_response :created

    assert_no_difference -> { @workspace.recurrences.count } do
      post "/api/v1/recurrences", params: { transaction_id: seed.id }, as: :json
    end
    assert_response :ok
  end

  test "POST /recurrences com transaction_id de outro workspace → 404" do
    foreign = create(:transaction, workspace: create(:workspace))
    post "/api/v1/recurrences", params: { transaction_id: foreign.id }, as: :json
    assert_response :not_found
  end

  # RF9.7 — exclusões: remover/restaurar item do grupo.
  test "POST /recurrences/:id/exclusions remove o item do grupo" do
    rec = create(:recurrence, workspace: @workspace, account: @account, descriptor_pattern: "NETFLIX COM")
    keep = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                  status: "consolidated", original_description: "NETFLIX.COM 1", occurred_at: Date.new(2026, 1, 10))
    drop = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                  status: "consolidated", original_description: "NETFLIX.COM 2", occurred_at: Date.new(2026, 2, 10))

    assert_difference -> { rec.exclusions.count }, 1 do
      post "/api/v1/recurrences/#{rec.id}/exclusions", params: { transaction_id: drop.id }, as: :json
    end
    assert_response :created
    assert_equal [ keep.id ], rec.reload.occurrences.map(&:id)
  end

  test "POST exclusions duas vezes não duplica (idempotente)" do
    rec = create(:recurrence, workspace: @workspace, account: @account, descriptor_pattern: "NETFLIX COM")
    drop = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                  status: "consolidated", original_description: "NETFLIX.COM 2", occurred_at: Date.new(2026, 2, 10))
    post "/api/v1/recurrences/#{rec.id}/exclusions", params: { transaction_id: drop.id }, as: :json
    assert_response :created
    assert_no_difference -> { rec.exclusions.count } do
      post "/api/v1/recurrences/#{rec.id}/exclusions", params: { transaction_id: drop.id }, as: :json
    end
    assert_response :ok
  end

  test "DELETE /recurrences/:id/exclusions/:transaction_id restaura o item" do
    rec = create(:recurrence, workspace: @workspace, account: @account, descriptor_pattern: "NETFLIX COM")
    drop = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                  status: "consolidated", original_description: "NETFLIX.COM 2", occurred_at: Date.new(2026, 2, 10))
    create(:recurrence_exclusion, recurrence: rec, excluded_transaction: drop, workspace: @workspace)

    assert_difference -> { rec.exclusions.count }, -1 do
      delete "/api/v1/recurrences/#{rec.id}/exclusions/#{drop.id}"
    end
    assert_response :no_content
  end

  test "exclusions de recorrência de outro workspace → 404" do
    foreign = create(:recurrence, workspace: create(:workspace))
    tx = create(:transaction, workspace: @workspace, account: @account, direction: "debit")
    post "/api/v1/recurrences/#{foreign.id}/exclusions", params: { transaction_id: tx.id }, as: :json
    assert_response :not_found
  end

  test "GET /recurrences/:id/transactions marca excluídos" do
    rec = create(:recurrence, workspace: @workspace, account: @account, descriptor_pattern: "NETFLIX COM")
    keep = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                  status: "consolidated", original_description: "NETFLIX.COM 1", occurred_at: Date.new(2026, 1, 10))
    drop = create(:transaction, workspace: @workspace, account: @account, direction: "debit",
                  status: "consolidated", original_description: "NETFLIX.COM 2", occurred_at: Date.new(2026, 2, 10))
    create(:recurrence_exclusion, recurrence: rec, excluded_transaction: drop, workspace: @workspace)

    get "/api/v1/recurrences/#{rec.id}/transactions"
    txs = JSON.parse(response.body)["transactions"]
    by_id = txs.index_by { |t| t["id"] }
    assert_equal false, by_id[keep.id]["excluded"]
    assert_equal true,  by_id[drop.id]["excluded"]
  end

  test "POST /recurrences sem descriptor → 422" do
    post "/api/v1/recurrences",
         params: { account_id: @account.id, cadence: "monthly" }, as: :json
    assert_response :unprocessable_entity
  end

  test "POST /recurrences com account de outro workspace → 422" do
    foreign = create(:account, workspace: create(:workspace))
    post "/api/v1/recurrences",
         params: { account_id: foreign.id, descriptor_pattern: "X", cadence: "monthly" }, as: :json
    assert_response :unprocessable_entity
  end

  test "PATCH /recurrences/:id altera tolerância e pausa" do
    rec = create(:recurrence, workspace: @workspace, account: @account)
    patch "/api/v1/recurrences/#{rec.id}",
          params: { amount_tolerance_pct: 12.5, status: "paused" }, as: :json
    assert_response :ok
    rec.reload
    assert_equal 12.5, rec.amount_tolerance_pct.to_f
    assert_equal "paused", rec.status
  end

  test "PATCH de outro workspace → 404" do
    foreign = create(:recurrence, workspace: create(:workspace))
    patch "/api/v1/recurrences/#{foreign.id}", params: { status: "cancelled" }, as: :json
    assert_response :not_found
  end

  test "DELETE /recurrences/:id remove" do
    rec = create(:recurrence, workspace: @workspace, account: @account)
    assert_difference -> { Recurrence.count }, -1 do
      delete "/api/v1/recurrences/#{rec.id}"
    end
    assert_response :no_content
  end

  test "DELETE de outro workspace → 404" do
    foreign = create(:recurrence, workspace: create(:workspace))
    delete "/api/v1/recurrences/#{foreign.id}"
    assert_response :not_found
    assert Recurrence.exists?(foreign.id)
  end

  # RF9.3 — vencimentos previstos para os próximos N dias.
  test "GET /recurrences/upcoming retorna ativas com vencimento na janela" do
    soon = create(:recurrence, workspace: @workspace, account: @account,
                  descriptor_pattern: "NETFLIX COM", next_expected_at: Date.current + 5)
    create(:recurrence, workspace: @workspace, account: @account,
           descriptor_pattern: "ANUAL", next_expected_at: Date.current + 40)
    create(:recurrence, workspace: @workspace, account: @account,
           descriptor_pattern: "PAUSADA", status: "paused", next_expected_at: Date.current + 3)
    create(:recurrence, workspace: create(:workspace), descriptor_pattern: "ALHEIA",
           next_expected_at: Date.current + 2)

    get "/api/v1/recurrences/upcoming?days=15"
    assert_response :ok
    recs = JSON.parse(response.body)["recurrences"]
    assert_equal [ "NETFLIX COM" ], recs.map { |r| r["descriptor_pattern"] }
    assert_equal 5, recs.first["days_until"]
  end

  test "GET /recurrences/upcoming?days= amplia a janela" do
    create(:recurrence, workspace: @workspace, account: @account,
           descriptor_pattern: "MENSAL", next_expected_at: Date.current + 5)
    create(:recurrence, workspace: @workspace, account: @account,
           descriptor_pattern: "DAQUI 40", next_expected_at: Date.current + 40)

    get "/api/v1/recurrences/upcoming?days=60"
    recs = JSON.parse(response.body)["recurrences"]
    assert_equal [ "MENSAL", "DAQUI 40" ], recs.map { |r| r["descriptor_pattern"] }
  end

  test "GET /recurrences/upcoming exige auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/recurrences/upcoming"
    assert_response :unauthorized
  end

  # RF9.6 — recorrente esperada que não chegou no prazo.
  test "GET /recurrences/:id/missed → atrasada quando não chegou" do
    rec = create(:recurrence, workspace: @workspace, account: @account,
                 descriptor_pattern: "NETFLIX COM", next_expected_at: Date.current - 10)

    get "/api/v1/recurrences/#{rec.id}/missed"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal true, body["missed"]
    assert_equal 10, body["days_overdue"]
    assert_nil body["last_seen_at"]
  end

  test "GET /recurrences/:id/missed → não atrasada quando a transação chegou" do
    rec = create(:recurrence, workspace: @workspace, account: @account,
                 descriptor_pattern: "NETFLIX COM", next_expected_at: Date.current - 10)
    create(:transaction, workspace: @workspace, account: @account, direction: "debit",
           original_description: "NETFLIX.COM 8821", amount_cents: 5990,
           occurred_at: Date.current - 5, status: "consolidated", consolidated_at: Time.current)

    get "/api/v1/recurrences/#{rec.id}/missed"
    body = JSON.parse(response.body)
    assert_equal false, body["missed"]
    assert_equal (Date.current - 5).iso8601, body["last_seen_at"]
  end

  test "GET /recurrences/:id/missed → não atrasada quando vencimento é futuro" do
    rec = create(:recurrence, workspace: @workspace, account: @account,
                 next_expected_at: Date.current + 7)
    get "/api/v1/recurrences/#{rec.id}/missed"
    assert_equal false, JSON.parse(response.body)["missed"]
  end

  test "GET /recurrences/:id/missed de outro workspace → 404" do
    foreign = create(:recurrence, workspace: create(:workspace))
    get "/api/v1/recurrences/#{foreign.id}/missed"
    assert_response :not_found
  end
end
