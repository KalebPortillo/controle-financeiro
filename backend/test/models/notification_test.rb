require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "factory builds a valid notification" do
    assert build(:notification).valid?
  end

  test "requires workspace, kind and payload" do
    notification = Notification.new
    assert_not notification.valid?
    assert_includes notification.errors[:workspace], "must exist"
    assert_includes notification.errors[:kind], "is not included in the list"
  end

  test "kind must be in the allowed set" do
    notification = build(:notification, kind: "bogus")
    assert_not notification.valid?
    assert_includes notification.errors[:kind], "is not included in the list"
  end

  test "recipient_membership is optional (NULL = broadcast)" do
    notification = build(:notification, recipient_membership: nil)
    assert notification.valid?
  end

  test "kind helpers" do
    assert build(:notification, kind: "sync_failed").sync_failed?
    assert build(:notification, kind: "inbox_new").inbox_new?
    assert build(:notification, kind: "recurrent_missed").recurrent_missed?
  end

  test "unread scope" do
    unread = create(:notification)
    create(:notification, workspace: unread.workspace, read_at: Time.current)

    assert_equal [ unread.id ], Notification.unread.pluck(:id)
  end

  test "visible_to inclui broadcast e dirigidas à membership, exclui de outra" do
    workspace  = create(:workspace)
    me         = create(:workspace_membership, workspace: workspace)
    other      = create(:workspace_membership, workspace: workspace)
    broadcast  = create(:notification, workspace: workspace)
    mine       = create(:notification, workspace: workspace, recipient_membership: me)
    create(:notification, workspace: workspace, recipient_membership: other)

    assert_equal [ broadcast.id, mine.id ].sort, Notification.visible_to(me).pluck(:id).sort
  end

  test "mark_read! seta read_at e é idempotente" do
    notification = create(:notification)
    notification.mark_read!
    first_read = notification.reload.read_at
    assert first_read.present?

    notification.mark_read!
    assert_equal first_read, notification.reload.read_at
  end

  test "dedup_key é único por workspace no banco" do
    notification = create(:notification, dedup_key: "recurrent_missed:abc:2026-06-01")

    assert_raises(ActiveRecord::RecordNotUnique) do
      create(:notification, workspace: notification.workspace,
                            dedup_key: "recurrent_missed:abc:2026-06-01")
    end
  end

  test "mesmo dedup_key em workspaces diferentes é permitido" do
    create(:notification, dedup_key: "sync_failed:x:2026-06-10")
    assert create(:notification, dedup_key: "sync_failed:x:2026-06-10").persisted?
  end

  test "dedup_key NULL não colide" do
    a = create(:notification, dedup_key: nil)
    b = create(:notification, workspace: a.workspace, dedup_key: nil)
    assert b.persisted?
  end
end
