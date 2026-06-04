class CreateSuggestedCategories < ActiveRecord::Migration[8.1]
  def change
    enable_extension "citext" unless extension_enabled?("citext")

    create_table :suggested_categories, id: :uuid do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.citext :name, null: false
      t.string :tag_names, array: true, default: [], null: false
      t.string :status, default: "pending", null: false

      t.timestamps
    end

    add_index :suggested_categories, [ :workspace_id, :name ], unique: true
    add_index :suggested_categories, [ :workspace_id, :status ]
    add_check_constraint :suggested_categories, "status IN ('pending', 'accepted', 'dismissed')", name: "suggested_categories_status_check"
  end
end
