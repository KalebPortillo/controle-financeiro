class CreateCategoryTags < ActiveRecord::Migration[8.1]
  def change
    create_table :category_tags, id: :uuid do |t|
      t.references :category, type: :uuid, null: false, foreign_key: true
      t.references :tag,      type: :uuid, null: false, foreign_key: true

      t.timestamps
    end

    # RF6.2: uma tag pode estar em N categorias, mas não repetida na mesma.
    add_index :category_tags, [ :category_id, :tag_id ], unique: true
  end
end
