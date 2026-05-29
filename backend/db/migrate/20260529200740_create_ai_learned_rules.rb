class CreateAiLearnedRules < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_learned_rules, id: :uuid do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.text :descriptor_pattern, null: false
      t.text :improved_title
      t.uuid :tag_ids, array: true, default: []
      t.integer :match_count, default: 1, null: false
      t.datetime :last_seen_at, null: false

      t.timestamps
    end

    add_index :ai_learned_rules, [ :workspace_id, :descriptor_pattern ],
              unique: true, name: "index_ai_learned_rules_on_workspace_and_pattern"
  end
end
