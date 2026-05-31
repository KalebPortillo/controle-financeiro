class CreateSuggestedTags < ActiveRecord::Migration[8.1]
  def change
    enable_extension "citext" unless extension_enabled?("citext")

    create_table :suggested_tags, id: :uuid do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.citext :name, null: false
      t.text :rationale
      t.integer :coverage, default: 0, null: false
      t.string :source, null: false
      t.string :status, default: "pending", null: false

      t.timestamps
    end

    add_index :suggested_tags, [ :workspace_id, :name ], unique: true
    add_index :suggested_tags, [ :workspace_id, :status ]
    add_check_constraint :suggested_tags, "source IN ('detected', 'manual', 'inbox')", name: "suggested_tags_source_check"
    add_check_constraint :suggested_tags, "status IN ('pending', 'accepted', 'dismissed')", name: "suggested_tags_status_check"
  end
end
