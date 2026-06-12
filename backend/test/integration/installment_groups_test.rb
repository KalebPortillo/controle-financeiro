require "test_helper"

# RF9.4.1 — edição em grupo de um parcelamento: título e tags valem para TODAS
# as parcelas (mesmo installment_group_id); valor/data seguem por parcela.
class InstallmentGroupsTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
    @account    = create(:account, workspace: @workspace, owner_membership: @membership)
    @group      = SecureRandom.uuid
  end

  def parcel(number, **attrs)
    create(:transaction, **{
      workspace: @workspace, account: @account, status: "pending",
      direction: "debit", amount_cents: 10_000, original_description: "GELADEIRA",
      installment_number: number, installment_total: 12, installment_group_id: @group,
      occurred_at: Date.new(2026, number, 1)
    }.merge(attrs))
  end

  test "PATCH aplica título e tags a todas as parcelas do grupo" do
    p1, p2, p3 = parcel(1), parcel(2), parcel(3)
    tag = create(:tag, workspace: @workspace, name: "Casa")

    patch "/api/v1/installment_groups/#{@group}",
          params: { improved_title: "Geladeira Brastemp", tag_ids: [ tag.id ] }, as: :json
    assert_response :ok

    [ p1, p2, p3 ].each do |p|
      p.reload
      assert_equal "Geladeira Brastemp", p.improved_title
      assert_equal [ "Casa" ], p.tags.pluck(:name)
    end
  end

  test "registra um TransactionEdit por parcela alterada" do
    p1, p2 = parcel(1), parcel(2)

    assert_difference -> { TransactionEdit.where(field_name: "improved_title").count }, 2 do
      patch "/api/v1/installment_groups/#{@group}",
            params: { improved_title: "Novo título" }, as: :json
    end
    assert_equal "Novo título", p1.reload.improved_title
    assert_equal "Novo título", p2.reload.improved_title
  end

  test "valor e data NÃO mudam (são por parcela)" do
    p1 = parcel(1, amount_cents: 10_000)
    p2 = parcel(2, amount_cents: 10_000)

    patch "/api/v1/installment_groups/#{@group}", params: { improved_title: "X" }, as: :json

    assert_equal 10_000, p1.reload.amount_cents
    assert_equal Date.new(2026, 2, 1), p2.reload.occurred_at
  end

  test "só tags (sem título)" do
    p1 = parcel(1, improved_title: "Mantém")
    tag = create(:tag, workspace: @workspace, name: "Eletro")

    patch "/api/v1/installment_groups/#{@group}", params: { tag_ids: [ tag.id ] }, as: :json
    assert_response :ok
    assert_equal "Mantém", p1.reload.improved_title
    assert_equal [ "Eletro" ], p1.tags.pluck(:name)
  end

  test "group_id desconhecido → 404" do
    patch "/api/v1/installment_groups/#{SecureRandom.uuid}",
          params: { improved_title: "X" }, as: :json
    assert_response :not_found
  end

  test "grupo de outro workspace → 404, sem efeito" do
    other = create(:workspace)
    other_acc = create(:account, workspace: other)
    alheia = create(:transaction, workspace: other, account: other_acc, status: "pending",
                                  direction: "debit", amount_cents: 100, original_description: "X",
                                  installment_number: 1, installment_total: 3,
                                  installment_group_id: SecureRandom.uuid)

    patch "/api/v1/installment_groups/#{alheia.installment_group_id}",
          params: { improved_title: "Invasor" }, as: :json
    assert_response :not_found
    assert_nil alheia.reload.improved_title
  end

  test "exige auth" do
    delete "/api/v1/sessions/current"
    patch "/api/v1/installment_groups/#{@group}", params: { improved_title: "X" }, as: :json
    assert_response :unauthorized
  end

  test "POST consolidate consolida todas as parcelas pendentes do grupo" do
    p1, p2, p3 = parcel(1), parcel(2), parcel(3)

    post "/api/v1/installment_groups/#{@group}/consolidate"
    assert_response :ok
    assert_equal 3, JSON.parse(response.body)["count"]

    [ p1, p2, p3 ].each do |p|
      assert_equal "consolidated", p.reload.status
      assert p.consolidated_at.present?
    end
  end

  test "POST consolidate não toca parcelas já consolidadas (conta só as pendentes)" do
    parcel(1)
    parcel(2, status: "consolidated", consolidated_at: 1.day.ago)

    post "/api/v1/installment_groups/#{@group}/consolidate"
    assert_equal 1, JSON.parse(response.body)["count"]
  end

  test "POST reject rejeita todas as parcelas pendentes do grupo" do
    p1, p2 = parcel(1), parcel(2)

    post "/api/v1/installment_groups/#{@group}/reject"
    assert_response :ok
    assert_equal 2, JSON.parse(response.body)["count"]
    assert_equal "rejected", p1.reload.status
    assert p2.reload.rejected_at.present?
  end

  test "consolidate de grupo inexistente → 404" do
    post "/api/v1/installment_groups/#{SecureRandom.uuid}/consolidate"
    assert_response :not_found
  end

  test "consolidate de grupo de outro workspace → 404, sem efeito" do
    other = create(:workspace)
    other_acc = create(:account, workspace: other)
    alheia = create(:transaction, workspace: other, account: other_acc, status: "pending",
                                  direction: "debit", amount_cents: 100, original_description: "X",
                                  installment_number: 1, installment_total: 3,
                                  installment_group_id: SecureRandom.uuid)

    post "/api/v1/installment_groups/#{alheia.installment_group_id}/consolidate"
    assert_response :not_found
    assert_equal "pending", alheia.reload.status
  end
end
