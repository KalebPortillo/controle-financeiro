require "test_helper"

# RF4.3 — trilha de alterações por transação: cada PATCH que muda um campo
# registra um TransactionEdit (quem, quando, de→para).
class TransactionEditsTest < ActionDispatch::IntegrationTest
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

  test "PATCH de título registra um edit com de→para e autor" do
    t = txn(improved_title: nil)
    assert_difference -> { t.edits.count }, 1 do
      patch "/api/v1/transactions/#{t.id}",
            params: { lock_version: t.lock_version, improved_title: "Almoço" }, as: :json
    end
    edit = t.edits.recent.first
    assert_equal "improved_title", edit.field_name
    assert_equal "Almoço", edit.new_value
    assert_equal @membership.id, edit.edited_by_membership_id
  end

  test "PATCH de valor + data registra dois edits" do
    t = txn(amount_cents: 1000, occurred_at: Date.new(2026, 5, 1))
    assert_difference -> { t.edits.count }, 2 do
      patch "/api/v1/transactions/#{t.id}",
            params: { lock_version: t.lock_version, amount_cents: 2000, occurred_at: "2026-05-10" },
            as: :json
    end
    fields = t.edits.pluck(:field_name).sort
    assert_equal [ "amount_cents", "occurred_at" ], fields
  end

  test "PATCH de tags registra um edit field_name=tags" do
    t = txn
    a = create(:tag, workspace: @workspace, name: "A")
    assert_difference -> { t.edits.count }, 1 do
      patch "/api/v1/transactions/#{t.id}",
            params: { lock_version: t.lock_version, tag_ids: [ a.id ] }, as: :json
    end
    assert_equal "tags", t.edits.recent.first.field_name
  end

  test "PATCH sem mudança real não registra edit" do
    t = txn(improved_title: "X")
    assert_no_difference -> { t.edits.count } do
      patch "/api/v1/transactions/#{t.id}",
            params: { lock_version: t.lock_version, improved_title: "X" }, as: :json
    end
  end

  test "GET /transactions/:id/edits lista mais recente primeiro" do
    t = txn(improved_title: nil, amount_cents: 1000)
    patch "/api/v1/transactions/#{t.id}", params: { lock_version: 0, improved_title: "A" }, as: :json
    patch "/api/v1/transactions/#{t.id}", params: { lock_version: 1, amount_cents: 5000 }, as: :json

    get "/api/v1/transactions/#{t.id}/edits"
    assert_response :ok
    edits = JSON.parse(response.body)["edits"]
    assert_equal 2, edits.size
    assert_equal "amount_cents", edits.first["field_name"] # mais recente
    assert_not_nil edits.first["edited_at"]
    assert_not_nil edits.first.dig("edited_by", "name")
  end

  test "GET edits de transação de outro workspace → 404" do
    other = create(:workspace)
    foreign = create(:transaction, workspace: other, account: create(:account, workspace: other))
    get "/api/v1/transactions/#{foreign.id}/edits"
    assert_response :not_found
  end
end
