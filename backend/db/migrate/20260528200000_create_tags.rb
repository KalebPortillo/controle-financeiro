class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.citext :name,  null: false
      t.string :color
      t.string :icon

      t.timestamps
    end

    # Tag é única por workspace (citext → case-insensitive). RF5.
    add_index :tags, [ :workspace_id, :name ], unique: true
  end
end
