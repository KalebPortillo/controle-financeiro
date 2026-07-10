require "test_helper"

class Transactions::DedupTest < ActiveSupport::TestCase
  def setup
    @account = create(:account, external_id: "acc-1")
  end

  # Cria uma automatic_sync com a assinatura fixa (variando só id/created_at).
  def dup(ext_id:, created_at:, **overrides)
    create(:transaction, {
      account:              @account,
      workspace:            @account.workspace,
      occurred_at:          Date.new(2026, 6, 26),
      amount_cents:         59_903,
      direction:            "debit",
      original_description: "Nike Us Stores",
      source:               "automatic_sync",
      source_metadata:      { "id" => ext_id },
      created_at:           created_at
    }.merge(overrides))
  end

  test "plan agrupa idênticas e não altera nada" do
    a = dup(ext_id: "a", created_at: 2.days.ago)
    b = dup(ext_id: "b", created_at: 1.day.ago)

    plan = Transactions::Dedup.plan
    assert_equal 1, plan.size
    group = plan.first
    assert_equal [ a.id, b.id ].sort, ([ group.survivor ] + group.doomed).map(&:id).sort
    assert_equal 2, Transaction.count, "dry-run não remove nada"
  end

  test "run! mantém uma e remove as demais" do
    dup(ext_id: "a", created_at: 2.days.ago)
    dup(ext_id: "b", created_at: 1.day.ago)

    assert_equal 1, Transactions::Dedup.run!
    assert_equal 1, Transaction.count
  end

  test "não toca em transações com assinaturas diferentes" do
    dup(ext_id: "a", created_at: 2.days.ago)
    dup(ext_id: "b", created_at: 1.day.ago)
    solo = dup(ext_id: "c", created_at: 1.hour.ago, amount_cents: 100)

    Transactions::Dedup.run!
    assert Transaction.exists?(solo.id)
  end

  test "elege como sobrevivente a que tem consolidação/edições e herda título/tags" do
    tag  = create(:tag, workspace: @account.workspace)
    rich = dup(ext_id: "rich", created_at: 2.days.ago, status: "consolidated", improved_title: "Nike")
    rich.tags << tag
    poor = dup(ext_id: "poor", created_at: 1.day.ago, improved_title: nil)

    Transactions::Dedup.run!

    assert Transaction.exists?(rich.id)
    assert_not Transaction.exists?(poor.id)
    assert_equal "Nike", rich.reload.improved_title
  end

  test "migra o vínculo de IOF quando ele está só na duplicata (caso invertido)" do
    # Sobrevivente = a que tem o vínculo, mesmo sendo a mais nova.
    plain  = dup(ext_id: "plain", created_at: 2.days.ago, improved_title: "Compra")
    linked = dup(ext_id: "linked", created_at: 1.day.ago)
    iof = create(:transaction, account: @account, workspace: @account.workspace,
                               direction: "debit", amount_cents: 210,
                               original_description: "IOF de compra internacional",
                               source: "automatic_sync", source_metadata: { "id" => "iof" })
    create(:transaction_link, workspace: @account.workspace,
                              primary_transaction: linked, related_transaction: iof,
                              relation_type: "iof")

    Transactions::Dedup.run!

    survivor = Transaction.where(id: [ plain.id, linked.id ]).first
    assert_equal linked.id, survivor.id, "sobrevive a que tem o vínculo"
    assert_equal survivor.id, iof.reload.link_as_related.primary_transaction_id
    # título da que morreu é herdado
    assert_equal "Compra", survivor.reload.improved_title
  end
end
