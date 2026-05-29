class AddAiSuggestionToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :ai_suggestion, :jsonb
  end
end
