class CreateRecurrences < ActiveRecord::Migration[8.1]
  def change
    create_table :recurrences, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :account,   type: :uuid, null: false, foreign_key: true
      t.string  :descriptor_pattern, null: false
      t.integer :expected_amount_cents
      t.decimal :amount_tolerance_pct, precision: 4, scale: 2, null: false, default: "5.00"
      t.string  :cadence, null: false
      t.date    :next_expected_at
      t.string  :status, null: false, default: "active"
      t.string  :source, null: false

      t.timestamps
    end

    add_index :recurrences, [ :workspace_id, :status ]

    add_check_constraint :recurrences,
      "cadence IN ('weekly','monthly','yearly','custom')", name: "recurrences_cadence_check"
    add_check_constraint :recurrences,
      "status IN ('active','paused','cancelled')", name: "recurrences_status_check"
    add_check_constraint :recurrences,
      "source IN ('detected','manual')", name: "recurrences_source_check"
    add_check_constraint :recurrences,
      "expected_amount_cents IS NULL OR expected_amount_cents > 0", name: "recurrences_amount_positive"
  end
end
