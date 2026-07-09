class AddRefundAutoLinkedNotificationKind < ActiveRecord::Migration[8.0]
  KINDS = %w[inbox_new budget_warning budget_exceeded recurrent_missed
             sync_failed import_completed refund_auto_linked].freeze

  def up
    remove_check_constraint :notifications, name: "notifications_kind_check"
    add_check_constraint :notifications, kind_in(KINDS), name: "notifications_kind_check"
  end

  def down
    remove_check_constraint :notifications, name: "notifications_kind_check"
    add_check_constraint :notifications, kind_in(KINDS - %w[refund_auto_linked]),
                         name: "notifications_kind_check"
  end

  def kind_in(kinds)
    list = kinds.map { |k| "'#{k}'" }.join(", ")
    "kind::text = ANY (ARRAY[#{list}]::text[])"
  end
end
