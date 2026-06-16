require "test_helper"

# RF2.3 — inbox em tempo real. Escopado por workspace_id: só membros assinam;
# o broadcast carrega o status atualizado da transação.
class TransactionsChannelTest < ActionCable::Channel::TestCase
  setup do
    @user      = create(:user)
    @workspace = create(:workspace)
    create(:workspace_membership, user: @user, workspace: @workspace)
  end

  test "membro do workspace assina e ganha o stream" do
    stub_connection current_user: @user
    subscribe(workspace_id: @workspace.id)

    assert subscription.confirmed?
    assert_has_stream_for @workspace
  end

  test "não-membro tem a assinatura rejeitada" do
    alheio = create(:workspace)
    stub_connection current_user: @user
    subscribe(workspace_id: alheio.id)

    assert subscription.rejected?
  end

  test "sem workspace_id rejeita" do
    stub_connection current_user: @user
    subscribe

    assert subscription.rejected?
  end
end
