# M:N entre um orçamento composto (RF8.3) e as tags que o compõem.
class BudgetCompositeTag < ApplicationRecord
  belongs_to :budget
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :budget_id }
end
