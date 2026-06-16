require "test_helper"

# RF3.6 — regras aprendidas pela IA: listagem (mais recentes primeiro, escopadas
# ao workspace) e remoção. O endpoint deleta dado do usuário, então cobrimos
# escopo e autenticação.
class AiLearnedRulesTest < ActionDispatch::IntegrationTest
  setup do
    @user      = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
  end

  test "GET /ai_learned_rules lista regras do workspace, mais recentes primeiro" do
    create(:ai_learned_rule, workspace: @workspace,
                             descriptor_pattern: "antiga", last_seen_at: 2.days.ago)
    recente = create(:ai_learned_rule, workspace: @workspace,
                                       descriptor_pattern: "recente", last_seen_at: 1.hour.ago)
    create(:ai_learned_rule, workspace: create(:workspace), descriptor_pattern: "alheia")

    get "/api/v1/ai_learned_rules"
    assert_response :ok
    rules = JSON.parse(response.body)["ai_learned_rules"]
    assert_equal %w[recente antiga], rules.map { |r| r["descriptor_pattern"] }
    assert_equal recente.id, rules.first["id"]
    assert_equal recente.last_seen_at.iso8601, rules.first["last_seen_at"]
  end

  test "DELETE /ai_learned_rules/:id remove a regra do workspace" do
    rule = create(:ai_learned_rule, workspace: @workspace)

    assert_difference("AiLearnedRule.count", -1) do
      delete "/api/v1/ai_learned_rules/#{rule.id}"
    end
    assert_response :no_content
  end

  test "DELETE /ai_learned_rules/:id de outro workspace → 404, sem apagar" do
    rule = create(:ai_learned_rule, workspace: create(:workspace))

    assert_no_difference("AiLearnedRule.count") do
      delete "/api/v1/ai_learned_rules/#{rule.id}"
    end
    assert_response :not_found
  end

  test "exige autenticação" do
    delete "/api/v1/sessions/current" # sign out
    get "/api/v1/ai_learned_rules"
    assert_response :unauthorized
  end
end
