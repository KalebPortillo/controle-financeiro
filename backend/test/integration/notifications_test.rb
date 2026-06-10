require "test_helper"

# RF17 — notificações in-app: listar (com filtro unread), marcar lida,
# marcar todas como lidas. Escopado por workspace.
class NotificationsTest < ActionDispatch::IntegrationTest
  setup do
    @user       = create(:user)
    sign_in_as(@user)
    @membership = @user.workspace_memberships.first
    @workspace  = @membership.workspace
  end

  test "GET /notifications lista por created_at desc com unread_count" do
    old_n  = create(:notification, workspace: @workspace, created_at: 2.days.ago)
    new_n  = create(:notification, workspace: @workspace, kind: "inbox_new")
    read_n = create(:notification, workspace: @workspace, read_at: Time.current, created_at: 1.day.ago)
    create(:notification) # outro workspace

    get "/api/v1/notifications"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal [ new_n.id, read_n.id, old_n.id ], body["notifications"].map { |n| n["id"] }
    assert_equal 2, body["unread_count"]
  end

  test "GET /notifications?unread=true filtra não lidas" do
    unread = create(:notification, workspace: @workspace)
    create(:notification, workspace: @workspace, read_at: Time.current)

    get "/api/v1/notifications", params: { unread: "true" }
    body = JSON.parse(response.body)
    assert_equal [ unread.id ], body["notifications"].map { |n| n["id"] }
  end

  test "GET /notifications esconde dirigidas a outra membership" do
    other = create(:workspace_membership, workspace: @workspace)
    mine      = create(:notification, workspace: @workspace, recipient_membership: @membership)
    broadcast = create(:notification, workspace: @workspace)
    create(:notification, workspace: @workspace, recipient_membership: other)

    get "/api/v1/notifications"
    ids = JSON.parse(response.body)["notifications"].map { |n| n["id"] }
    assert_equal [ mine.id, broadcast.id ].sort, ids.sort
  end

  test "GET /notifications exige auth" do
    delete "/api/v1/sessions/current"
    get "/api/v1/notifications"
    assert_response :unauthorized
  end

  test "POST /notifications/:id/mark_read marca e retorna a notificação" do
    notification = create(:notification, workspace: @workspace)

    post "/api/v1/notifications/#{notification.id}/mark_read"
    assert_response :ok
    assert notification.reload.read_at.present?
    assert JSON.parse(response.body).dig("notification", "read_at").present?
  end

  test "POST mark_read de outro workspace → 404" do
    alheia = create(:notification)

    post "/api/v1/notifications/#{alheia.id}/mark_read"
    assert_response :not_found
    assert_nil alheia.reload.read_at
  end

  test "POST /notifications/mark_all_read zera o contador" do
    create_list(:notification, 3, workspace: @workspace)
    create(:notification) # outro workspace, intocada

    post "/api/v1/notifications/mark_all_read"
    assert_response :ok
    assert_equal 0, @workspace.notifications.unread.count
    assert_equal 1, Notification.unread.count
  end
end
