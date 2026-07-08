class CreateBudgets < ActiveRecord::Migration[8.1]
  def change
    create_table :budgets, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: true
      t.string  :name, null: false
      t.string  :kind, null: false
      t.references :target_tag,      type: :uuid, null: true, foreign_key: { to_table: :tags }
      t.references :target_category, type: :uuid, null: true, foreign_key: { to_table: :categories }
      t.integer :monthly_limit_cents, null: false
      t.date    :starts_on
      t.date    :ends_on
      t.integer :alert_threshold_pct, null: false, default: 80, limit: 2
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    # Consistência kind ↔ alvo (RF8): tag aponta target_tag; category aponta
    # target_category; composite não aponta nenhum (usa budget_composite_tags).
    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER TABLE budgets
            ADD CONSTRAINT budgets_kind_target_check CHECK (
              (kind = 'tag'       AND target_tag_id IS NOT NULL AND target_category_id IS NULL) OR
              (kind = 'category'  AND target_category_id IS NOT NULL AND target_tag_id IS NULL) OR
              (kind = 'composite' AND target_tag_id IS NULL AND target_category_id IS NULL)
            ),
            ADD CONSTRAINT budgets_kind_check CHECK (kind IN ('tag','category','composite')),
            ADD CONSTRAINT budgets_limit_positive_check CHECK (monthly_limit_cents > 0);
        SQL
      end
      dir.down do
        execute <<~SQL
          ALTER TABLE budgets
            DROP CONSTRAINT IF EXISTS budgets_kind_target_check,
            DROP CONSTRAINT IF EXISTS budgets_kind_check,
            DROP CONSTRAINT IF EXISTS budgets_limit_positive_check;
        SQL
      end
    end

    create_table :budget_composite_tags, id: false do |t|
      t.references :budget, type: :uuid, null: false, foreign_key: true
      t.references :tag,    type: :uuid, null: false, foreign_key: true
    end
    add_index :budget_composite_tags, [ :budget_id, :tag_id ], unique: true
  end
end
