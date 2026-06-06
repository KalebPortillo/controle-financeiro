class CreateCategoryTagSuggestions < ActiveRecord::Migration[8.1]
  def change
    # Sugestão da IA de uma tag JÁ existente que ainda não está na categoria
    # (on-demand, persistida pra revisar depois). Status pending/accepted/dismissed.
    create_table :category_tag_suggestions, id: :uuid do |t|
      t.references :category, null: false, foreign_key: true, type: :uuid
      t.references :tag,      null: false, foreign_key: true, type: :uuid
      t.string :status, null: false, default: "pending"
      t.timestamps
    end

    add_index :category_tag_suggestions, [ :category_id, :tag_id ], unique: true
  end
end
