require "test_helper"

# Busca textual (Fase 1) — GET /api/v1/transactions?q=. Acento-insensível e por
# substring sobre título atual, descrição original do banco e nomes de tags.
class TransactionsSearchTest < ActionDispatch::IntegrationTest
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

  def search(q)
    get "/api/v1/transactions", params: { q: q }
    JSON.parse(response.body)["transactions"].map { |t| t["id"] }
  end

  test "q em branco não filtra (retorna tudo)" do
    a = txn(original_description: "Padaria")
    b = txn(original_description: "Mercado")

    assert_equal [ a.id, b.id ].sort, search("").sort
  end

  test "acha por substring do título melhorado" do
    hit  = txn(improved_title: "Amazon Prime", original_description: "AMZN MKTP US")
    miss = txn(improved_title: "Spotify",      original_description: "SPOTIFY BR")

    ids = search("amaz")
    assert_includes ids, hit.id
    assert_not_includes ids, miss.id
  end

  test "acha pela descrição original do banco mesmo com título diferente" do
    hit = txn(improved_title: "Amazon Prime", original_description: "AMZN MKTP US*2K4")

    assert_includes search("mktp"), hit.id
  end

  test "busca é acento-insensível nos dois sentidos" do
    com_acento = txn(improved_title: "Açaí da Praia")
    sem_acento = txn(improved_title: "Cafe Central")

    assert_includes search("acai"), com_acento.id
    assert_includes search("café"), sem_acento.id
  end

  test "acha por nome de tag aplicada à transação" do
    tag = create(:tag, workspace: @workspace, name: "Alimentação")
    hit = txn(improved_title: "Compra X")
    hit.tags << tag
    miss = txn(improved_title: "Compra Y")

    ids = search("aliment")
    assert_includes ids, hit.id
    assert_not_includes ids, miss.id
  end

  test "não vaza transações de outro workspace" do
    mine = txn(improved_title: "Amazon")
    other_ws = create(:workspace)
    other_acc = create(:account, workspace: other_ws)
    create(:transaction, workspace: other_ws, account: other_acc, status: "pending",
           improved_title: "Amazon")

    assert_equal [ mine.id ], search("amazon")
  end

  test "busca global tem teto defensivo de resultados" do
    limit = Api::V1::TransactionsController::SEARCH_RESULTS_LIMIT
    now = Time.current
    rows = (limit + 1).times.map do |i|
      { workspace_id: @workspace.id, account_id: @account.id, direction: "debit",
        amount_cents: 100 + i, occurred_at: Date.current - (i % 90),
        original_description: "PIX MERCADO #{i}", status: "pending",
        source: "automatic_sync", source_metadata: { "id" => "bulk-#{i}" },
        created_at: now, updated_at: now }
    end
    Transaction.insert_all(rows)

    assert_equal limit, search("pix").size
  end
end
