class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.citext :name,  null: false
      t.string :color
      t.string :icon

      t.timestamps
    end

    add_index :categories, [ :workspace_id, :name ], unique: true
  end
end
