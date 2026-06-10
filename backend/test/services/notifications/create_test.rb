require "test_helper"

module Notifications
  class CreateTest < ActiveSupport::TestCase
    include ActionCable::TestHelper
    include ActiveJob::TestHelper

    setup do
      @workspace = create(:workspace)
    end

    test "persiste a notificação com kind e payload" do
      notification = Notifications::Create.call(
        workspace: @workspace, kind: "sync_failed",
        payload: { "institution_label" => "Nubank", "error_message" => "expirou" }
      )

      assert notification.persisted?
      assert_equal "sync_failed", notification.kind
      assert_equal "Nubank", notification.payload["institution_label"]
      assert_nil notification.recipient_membership_id
    end

    test "broadcasta notification_created no canal do workspace" do
      stream = NotificationsChannel.broadcasting_for(@workspace)

      assert_broadcasts(stream, 1) do
        Notifications::Create.call(workspace: @workspace, kind: "inbox_new",
                                   payload: { "count" => 3 })
      end
    end

    test "payload do broadcast tem o schema do serializer" do
      stream = NotificationsChannel.broadcasting_for(@workspace)

      notification = Notifications::Create.call(workspace: @workspace, kind: "inbox_new",
                                                payload: { "count" => 1 })

      message = JSON.parse(broadcasts(stream).last)
      assert_equal "notification_created", message["event"]
      assert_equal notification.id, message.dig("notification", "id")
      assert_equal "inbox_new", message.dig("notification", "kind")
      assert_equal({ "count" => 1 }, message.dig("notification", "payload"))
      assert_nil message.dig("notification", "read_at")
    end

    test "dedup: segunda chamada com a mesma dedup_key retorna nil sem criar" do
      first = Notifications::Create.call(
        workspace: @workspace, kind: "recurrent_missed",
        payload: { "recurrence_id" => "abc" }, dedup_key: "recurrent_missed:abc:2026-06-01"
      )
      assert first.persisted?

      second = assert_no_difference("Notification.count") do
        Notifications::Create.call(
          workspace: @workspace, kind: "recurrent_missed",
          payload: { "recurrence_id" => "abc" }, dedup_key: "recurrent_missed:abc:2026-06-01"
        )
      end
      assert_nil second
    end

    test "dedup hit não broadcasta" do
      Notifications::Create.call(workspace: @workspace, kind: "recurrent_missed",
                                 payload: {}, dedup_key: "x")
      stream = NotificationsChannel.broadcasting_for(@workspace)

      assert_no_broadcasts(stream) do
        Notifications::Create.call(workspace: @workspace, kind: "recurrent_missed",
                                   payload: {}, dedup_key: "x")
      end
    end

    test "aceita recipient_membership dirigida" do
      membership = create(:workspace_membership, workspace: @workspace)
      notification = Notifications::Create.call(
        workspace: @workspace, kind: "sync_failed", payload: {},
        recipient_membership: membership
      )

      assert_equal membership.id, notification.recipient_membership_id
    end

    test "não enfileira nada de Telegram (workspace sem vínculo)" do
      assert_no_enqueued_jobs do
        Notifications::Create.call(workspace: @workspace, kind: "inbox_new",
                                   payload: { "count" => 2 })
      end
    end
  end
end
