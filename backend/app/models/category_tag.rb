# Junção M:N entre Category e Tag (RF6.2).
class CategoryTag < ApplicationRecord
  belongs_to :category
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :category_id }
end
