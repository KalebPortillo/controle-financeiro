require "test_helper"

class AiSuggestion::RecordCorrectionJobTest < ActiveJob::TestCase
  setup do
    @workspace = create(:workspace)
    @account   = create(:account, workspace: @workspace)
    @tag1      = create(:tag, workspace: @workspace, name: "Mercado")
  end

  test "creates a learned rule from the normalized descriptor" do
    tx = create(:transaction,
                workspace: @workspace, account: @account,
                original_description: "PGTO PIX 43958 MERCADO ABC LTDA",
                improved_title: "Mercado ABC")
    tx.tags << @tag1

    assert_difference "AiLearnedRule.count", 1 do
      AiSuggestion::RecordCorrectionJob.perform_now(tx.id)
    end

    rule = AiLearnedRule.last
    assert_equal @workspace.id,       rule.workspace_id
    assert_equal "pgto pix mercado abc ltda", rule.descriptor_pattern
    assert_equal "Mercado ABC",       rule.improved_title
    assert_equal [ @tag1.id ],        rule.tag_ids
    assert_equal 1,                   rule.match_count
  end

  test "increments match_count when same pattern repeats" do
    tx1 = create(:transaction, workspace: @workspace, account: @account,
                  original_description: "MERCADO ABC", improved_title: "Mercado ABC")
    tx1.tags << @tag1
    tx2 = create(:transaction, workspace: @workspace, account: @account,
                  original_description: "MERCADO ABC", improved_title: "Mercado ABC")
    tx2.tags << @tag1

    AiSuggestion::RecordCorrectionJob.perform_now(tx1.id)
    assert_no_difference "AiLearnedRule.count" do
      AiSuggestion::RecordCorrectionJob.perform_now(tx2.id)
    end

    rule = AiLearnedRule.first
    assert_equal 2, rule.match_count
  end

  test "updates improved_title and tag_ids when user corrects again" do
    tx1 = create(:transaction, workspace: @workspace, account: @account,
                  original_description: "MERCADO ABC", improved_title: "Mercado")
    tx1.tags << @tag1
    AiSuggestion::RecordCorrectionJob.perform_now(tx1.id)

    tag2 = create(:tag, workspace: @workspace, name: "Supermercado")
    tx2 = create(:transaction, workspace: @workspace, account: @account,
                  original_description: "MERCADO ABC", improved_title: "Mercado Atualizado")
    tx2.tags << tag2

    AiSuggestion::RecordCorrectionJob.perform_now(tx2.id)

    rule = AiLearnedRule.first
    assert_equal "Mercado Atualizado", rule.improved_title
    assert_equal [ tag2.id ],          rule.tag_ids
  end

  test "no-op when descriptor normalizes to empty" do
    tx = create(:transaction, workspace: @workspace, account: @account,
                original_description: "12345", improved_title: "Mercado")

    assert_no_difference "AiLearnedRule.count" do
      AiSuggestion::RecordCorrectionJob.perform_now(tx.id)
    end
  end

  test "no-op when transaction does not exist" do
    assert_nothing_raised do
      AiSuggestion::RecordCorrectionJob.perform_now("00000000-0000-0000-0000-000000000000")
    end
  end
end
